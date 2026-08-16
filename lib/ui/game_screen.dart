import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../camera/reaction_camera.dart';
import '../../models/game_state.dart';
import '../../networking/game_message.dart';
import '../../networking/game_transport.dart';
import '../../networking/webrtc/lan_webrtc_video.dart';
import '../../networking/webrtc/webrtc_qr_session.dart';
import '../../share/share_service.dart';
import '../../state/chat_controller.dart';
import '../../state/game_controller.dart';
import '../../util/blush_log.dart';
import '../../util/camera_availability.dart';
import 'av_consent.dart';
import 'theme.dart';
import 'widgets/card_face.dart';
import 'widgets/chat_panel.dart';
import 'widgets/hand_strip.dart';
import 'widgets/reaction_pip.dart';
import 'widgets/score_pips.dart';
import 'widgets/share_button.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    this.session,
    this.chat,
    required this.onLeave,
  });

  final GameController controller;
  final GameSession? session;
  final ChatController? chat;
  final VoidCallback onLeave;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  int? _selectedChoiceId;
  final _av = ReactionAvController();
  final _share = const ShareService();
  String? _peerFrameBase64;
  Timer? _frameTimer;
  final _prizeController = TextEditingController();
  ReactionAvLayoutPref _avLayoutPref = ReactionAvLayoutPref.auto;
  static const _avLayoutPrefKey = 'blushcraft_av_layout';
  bool _avConsentGiven = false;
  bool _avInitAttempted = false;
  bool _avInitFailed = false;
  int _frameFailStreak = 0;
  int _audioSendWireSeq = 0;
  DateTime? _lastAudioWireLog;
  DateTime? _lastLevelPrivacySend;
  Timer? _levelPrivacyTimer;
  LanWebrtcVideo? _lanVideo;

  LocalDiscoverySession? get _local =>
      widget.session is LocalDiscoverySession
          ? widget.session as LocalDiscoverySession
          : null;

  WebRtcQrSession? get _webrtc =>
      widget.session is WebRtcQrSession
          ? widget.session as WebRtcQrSession
          : null;

  /// Online path: A/V both on WebRTC tracks.
  bool get _useWebRtcMedia => _webrtc != null;

  /// Local live video uses WebRTC; JPEG stills are retired for Local.
  bool get _wantLanRtcVideo =>
      _local != null &&
      _av.bothLiveViewEnabled &&
      !_av.audioOnlyLiveMedia;

  /// Prefer getUserMedia via LAN WebRTC over CameraController when live media is on.
  bool get _preferLanRtcCamera =>
      _local != null && _av.liveViewEnabled && _av.deviceHasCamera;

  static const _prizePresets = [
    'Foot massage',
    'Breakfast in bed',
    'Pick next date night',
    'Winner\'s choice of movie',
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onGame);
    widget.controller.onPeerFrame = (id, b64) {
      if (!mounted || !_av.peerCameraEnabled) return;
      setState(() => _peerFrameBase64 = b64);
    };
    widget.controller.onPeerAudio = (id, b64, {required mime}) async {
      if (!_av.peerMicEnabled) {
        blushLog('Audio', 'wire recv dropped peerMic=false mime=$mime');
        return;
      }
      try {
        final bytes = base64Decode(b64);
        await _av.playPeerAudio(bytes, mime: mime);
      } catch (e) {
        blushLog('Audio', 'wire recv play failed: $e');
      }
    };
    widget.controller.onAvPrivacy = (id, {
      required cameraEnabled,
      required micEnabled,
      required liveViewEnabled,
      required hasCamera,
      required audioLevel,
    }) {
      if (!mounted) return;
      final peerLiveBefore = _av.peerLiveViewEnabled;
      _av.setPeerPrivacy(
        cameraOn: cameraEnabled,
        micOn: micEnabled,
        liveViewOn: liveViewEnabled,
        hasCamera: hasCamera,
        audioLevel: audioLevel,
      );
      blushLog(
        'AV',
        'peer privacy cam=$cameraEnabled mic=$micEnabled '
        'live=$liveViewEnabled hasCam=$hasCamera lvl=${audioLevel.toStringAsFixed(2)}',
      );
      if (!cameraEnabled) {
        setState(() => _peerFrameBase64 = null);
      } else {
        setState(() {});
      }
      unawaited(_syncLanVideo());
      // Handshake: lobby → game remounts wipe peer flags. When the peer
      // announces (especially live media), echo ours so both GameScreens sync.
      if (liveViewEnabled && !peerLiveBefore) {
        unawaited(_publishPrivacy());
      } else {
        unawaited(_publishPrivacyThrottled());
      }
    };
    widget.controller.onWebrtcVideoSignal = (msg) {
      unawaited(_onLanVideoSignal(msg));
    };
    _av.onLocalAudioChunk = (bytes, mime) {
      if (_useWebRtcMedia) return; // Online: audio via WebRTC tracks
      final session = widget.session;
      if (session == null || !session.isConnected) {
        blushLog('Audio', 'wire send skip notConnected bytes=${bytes.length}');
        return;
      }
      if (!_av.micEnabled) {
        blushLog('Audio', 'wire send skip micOff');
        return;
      }
      if (bytes.isEmpty) return;
      _audioSendWireSeq++;
      final b64 = base64Encode(bytes);
      final now = DateTime.now();
      if (_lastAudioWireLog == null ||
          now.difference(_lastAudioWireLog!) > const Duration(seconds: 2)) {
        _lastAudioWireLog = now;
        blushLog(
          'Audio',
          'wire send #$_audioSendWireSeq raw=${bytes.length} '
          'b64=${b64.length} mime=$mime',
        );
      }
      session.send(
        PeerAudioMessage(
          playerId: widget.controller.localPlayerId,
          base64Aac: b64,
          mime: mime,
        ),
      );
    };
    _av.addListener(_onAvChanged);
    _webrtc?.addListener(_onWebRtcChanged);
    unawaited(_loadAvPrefs());
    _onGame();
  }

  Future<void> _loadAvPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _avConsentGiven = await loadAvConsentGiven();
    final wants = await loadAvWantFlags();
    final hasCam = await deviceHasUsableCamera();
    await _av.setDeviceHasCamera(hasCam);
    if (!mounted) return;
    setState(() {
      _avLayoutPref =
          ReactionAvLayoutPref.fromStorage(prefs.getString(_avLayoutPrefKey));
    });
    if (!_avConsentGiven) return;
    if (wants.camera || wants.mic || wants.liveView) {
      if ((wants.camera || wants.liveView || wants.mic) && !_useWebRtcMedia) {
        final openCamera =
            wants.camera && !(_local != null && wants.liveView && hasCam);
        await _av.init(openCamera: openCamera);
      }
      // Never force camera on cameraless devices.
      if (wants.camera && hasCam) await _av.setCameraEnabled(true);
      if (wants.mic || (wants.liveView && !hasCam)) {
        await _av.setMicEnabled(true);
      }
      if (wants.liveView) await _av.setLiveViewEnabled(true);
      if (mounted) setState(() {});
      await _publishPrivacy();
      _onGame();
    }
  }

  Future<void> _persistAvWants() async {
    await saveAvWantFlags(
      camera: _av.cameraEnabled,
      mic: _av.micEnabled,
      liveView: _av.liveViewEnabled,
    );
  }

  Future<void> _cycleAvLayout() async {
    final next = _avLayoutPref.next;
    setState(() => _avLayoutPref = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_avLayoutPrefKey, next.storageValue);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next.label),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  void _onAvChanged() {
    final phase = widget.controller.state?.phase;
    // JPEG stills only as rare fallback — Local video is WebRTC now.
    if (_shouldStreamAv(phase) &&
        _av.cameraEnabled &&
        _av.liveViewEnabled &&
        !_av.audioOnlyLiveMedia &&
        !_useWebRtcMedia &&
        !_wantLanRtcVideo) {
      _startFrames();
    } else {
      _stopFrames();
    }
    unawaited(_syncLanVideo());
    _syncLevelPrivacyTimer();
    if (mounted) setState(() {});
  }

  void _onWebRtcChanged() {
    if (mounted) setState(() {});
  }

  void _onLanVideoChanged() {
    if (mounted) setState(() {});
  }

  void _onGame() {
    final phase = widget.controller.state?.phase;
    if (_shouldStreamAv(phase)) {
      // Publish off-by-default privacy; only touch hardware after consent.
      unawaited(_publishPrivacy());
      if (_useWebRtcMedia) {
        unawaited(_syncWebRtcTracks());
      } else if (_av.cameraEnabled || _av.micEnabled || _av.liveViewEnabled) {
        unawaited(_ensureAv());
      }
      unawaited(_syncLanVideo());
      if (!_av.liveViewEnabled || !_av.cameraEnabled || _wantLanRtcVideo) {
        _stopFrames();
      }
      _syncLevelPrivacyTimer();
    } else {
      _stopFrames();
      unawaited(_av.stopMic());
      unawaited(_lanVideo?.stop());
      _levelPrivacyTimer?.cancel();
      _levelPrivacyTimer = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _onLanVideoSignal(WebrtcVideoSignalMessage msg) async {
    if (_useWebRtcMedia || _local == null) return;
    final session = widget.session;
    if (session == null || !session.isConnected) return;
    if (_lanVideo == null) {
      _lanVideo = LanWebrtcVideo(
        isHost: widget.controller.isHost,
        send: session.send,
      );
      _lanVideo!.addListener(_onLanVideoChanged);
      blushLog(
        'LanRTC',
        'create bridge on signal isHost=${widget.controller.isHost}',
      );
    }
    await _lanVideo!.handleSignal(msg);
  }

  Future<void> _syncLanVideo() async {
    if (_useWebRtcMedia || _local == null) return;
    final session = widget.session;
    if (session == null || !session.isConnected) return;

    if (!_wantLanRtcVideo) {
      if (_lanVideo != null) {
        blushLog('LanRTC', 'teardown (audio-only or live media off)');
        await _lanVideo!.stop();
        _lanVideo!.removeListener(_onLanVideoChanged);
        _lanVideo!.dispose();
        _lanVideo = null;
        if (mounted) setState(() {});
      }
      return;
    }

    if (_lanVideo == null) {
      _lanVideo = LanWebrtcVideo(
        isHost: widget.controller.isHost,
        send: session.send,
      );
      _lanVideo!.addListener(_onLanVideoChanged);
      blushLog(
        'LanRTC',
        'create bridge isHost=${widget.controller.isHost}',
      );
    }
    await _lanVideo!.ensureStarted();
    await _lanVideo!.setLocalVideoEnabled(_av.cameraEnabled);
  }

  Future<void> _syncWebRtcTracks() async {
    await _webrtc?.setTrackEnabled(
      video: _av.cameraEnabled,
      audio: _av.micEnabled,
    );
  }

  bool _shouldStreamAv(GamePhase? phase) {
    switch (phase) {
      case GamePhase.selecting:
      case GamePhase.waitingForOpponent:
      case GamePhase.reveal:
      case GamePhase.reaction:
      case GamePhase.roundResult:
        return true;
      case GamePhase.gameOver:
      case GamePhase.disconnected:
      case GamePhase.lobby:
      case null:
        return false;
    }
  }

  Future<void> _ensureAv() async {
    // Don't hammer init every state tick when cameras are missing/broken.
    if (_avInitFailed) return;
    if (!_av.initialized && _avInitAttempted && !_av.initializing) {
      _avInitFailed = true;
      blushLog('AV', 'av init failed — continuing (mic/video may be limited)');
      _stopFrames();
      return;
    }
    _avInitAttempted = true;
    // Local WebRTC owns the camera device — avoid CameraController conflict.
    final openCamera = !_preferLanRtcCamera && !_useWebRtcMedia;
    final ok = await _av.init(openCamera: openCamera);
    if (!ok || !mounted) {
      if (!_av.initializing) {
        _avInitFailed = true;
        blushLog('AV', 'av unavailable (${_av.error}) — game continues');
        _stopFrames();
      }
      return;
    }
    _avInitFailed = false;
    if (_av.cameraEnabled &&
        _av.liveViewEnabled &&
        !_av.audioOnlyLiveMedia &&
        !_wantLanRtcVideo) {
      _startFrames();
    } else {
      _stopFrames();
    }
    if (_av.micEnabled) {
      await _av.startMic();
    }
    await _publishPrivacy();
    await _syncLanVideo();
  }

  Future<bool> _confirmAvConsent() async {
    if (_avConsentGiven) return true;
    final ok = await showAvConsentSheet(context);
    if (ok) _avConsentGiven = true;
    return ok;
  }

  Future<void> _publishPrivacy() async {
    final session = widget.session;
    if (session == null || !session.isConnected) return;
    await session.send(
      AvPrivacyMessage(
        playerId: widget.controller.localPlayerId,
        cameraEnabled: _av.cameraEnabled,
        micEnabled: _av.micEnabled,
        liveViewEnabled: _av.liveViewEnabled,
        hasCamera: _av.deviceHasCamera,
        audioLevel: _av.localDisplayAudioLevel,
      ),
    );
  }

  Future<void> _publishPrivacyThrottled() async {
    final now = DateTime.now();
    if (_lastLevelPrivacySend != null &&
        now.difference(_lastLevelPrivacySend!) <
            const Duration(milliseconds: 300)) {
      return;
    }
    _lastLevelPrivacySend = now;
    await _publishPrivacy();
  }

  void _syncLevelPrivacyTimer() {
    final need = _av.micEnabled &&
        _shouldStreamAv(widget.controller.state?.phase) &&
        widget.session?.isConnected == true;
    if (!need) {
      _levelPrivacyTimer?.cancel();
      _levelPrivacyTimer = null;
      return;
    }
    if (_levelPrivacyTimer != null) return;
    _levelPrivacyTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_av.micEnabled) return;
      unawaited(_publishPrivacyThrottled());
    });
  }

  void _startFrames() {
    if (_useWebRtcMedia) return;
    if (!_av.ready || !_av.cameraEnabled || !_av.liveViewEnabled) return;
    _frameFailStreak = 0;
    _frameTimer?.cancel();
    // ~2.5 fps target after compress; serialize captures to avoid overlap.
    _frameTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (!_av.cameraEnabled || !_av.ready) return;
      final b64 = await _av.captureBase64Jpeg(maxWidth: 320, quality: 55);
      if (b64 == null) {
        _frameFailStreak++;
        // Soft backoff — keep trying; do not permanently kill the timer.
        if (_frameFailStreak == 8) {
          blushLog('AV', 'capture struggling — still retrying');
        }
        return;
      }
      _frameFailStreak = 0;
      // Compressed frames should land well under this; drop pathological blobs.
      if (b64.length > 48 * 1024) {
        blushLog('AV', 'drop oversized peer frame chars=${b64.length}');
        return;
      }
      final session = widget.session;
      if (session == null || !session.isConnected) return;
      await session.send(
        PeerFrameMessage(
          playerId: widget.controller.localPlayerId,
          base64Jpeg: b64,
        ),
      );
    });
  }

  void _stopFrames() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  Future<void> _toggleCamera() async {
    if (!_av.deviceHasCamera) return;
    if (_av.cameraEnabled) {
      await _av.setCameraEnabled(false);
      _stopFrames();
      await _lanVideo?.setLocalVideoEnabled(false);
    } else {
      final ok = await _confirmAvConsent();
      if (!ok || !mounted) return;
      if (!_useWebRtcMedia && !_preferLanRtcCamera) {
        _avInitFailed = false;
        _avInitAttempted = false;
        final ready = await _av.init(openCamera: true);
        if (!ready || !mounted) {
          blushLog('AV', 'camera still unavailable — leaving camera off');
          return;
        }
      }
      await _av.setCameraEnabled(true);
      if (_preferLanRtcCamera || _wantLanRtcVideo) {
        await _syncLanVideo();
        await _lanVideo?.setLocalVideoEnabled(true);
      } else if (!_useWebRtcMedia) {
        _startFrames();
      }
    }
    await _webrtc?.setTrackEnabled(
      video: _av.cameraEnabled,
      audio: _av.micEnabled,
    );
    await _publishPrivacy();
    await _persistAvWants();
  }

  Future<void> _toggleMic() async {
    if (_av.micEnabled) {
      await _av.setMicEnabled(false);
    } else {
      final ok = await _confirmAvConsent();
      if (!ok || !mounted) return;
      await _av.setMicEnabled(true);
    }
    await _webrtc?.setTrackEnabled(
      video: _av.cameraEnabled,
      audio: _av.micEnabled,
    );
    await _publishPrivacy();
    await _persistAvWants();
  }

  @override
  void dispose() {
    _stopFrames();
    _levelPrivacyTimer?.cancel();
    widget.controller.removeListener(_onGame);
    widget.controller.onPeerFrame = null;
    widget.controller.onPeerAudio = null;
    widget.controller.onAvPrivacy = null;
    widget.controller.onWebrtcVideoSignal = null;
    _av.onLocalAudioChunk = null;
    _av.removeListener(_onAvChanged);
    _webrtc?.removeListener(_onWebRtcChanged);
    _lanVideo?.removeListener(_onLanVideoChanged);
    _lanVideo?.dispose();
    _lanVideo = null;
    _av.dispose();
    _prizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        if (state == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return BlushBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text(
                state.phase == GamePhase.gameOver
                    ? 'Game over'
                    : state.isTieBreaker
                        ? 'Round ${state.roundNumber} · Tie-breaker'
                        : 'Round ${state.roundNumber}',
              ),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onLeave,
              ),
              actions: [
                if (widget.chat != null &&
                    !widget.controller.dryRun &&
                    widget.session != null)
                  ChatAppBarButton(
                    chat: widget.chat!,
                    partnerName: state.remotePlayer.name,
                    enabled: widget.session!.isConnected,
                    captureReactionSelfie: (_av.cameraEnabled && _av.ready)
                        ? () => _av.captureBase64Jpeg()
                        : null,
                    onVoiceNoteRecording: (recording) async {
                      if (recording) {
                        await _av.stopMic();
                      } else if (_av.micEnabled) {
                        await _av.startMic();
                      }
                    },
                  ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  if (widget.chat != null)
                    ChatInviteBanner(
                      chat: widget.chat!,
                      partnerName: state.remotePlayer.name,
                    ),
                  if (widget.chat != null)
                    ChatIncomingToast(chat: widget.chat!),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ScorePips(
                      hostName: state.host.name,
                      guestName: state.guest.name,
                      hostScore: state.host.score,
                      guestScore: state.guest.score,
                      pointsToWin: state.pointsToWin,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: (_shouldStreamAv(state.phase) &&
                            _av.bothLiveViewEnabled)
                        ? _withReactionPip(state, _bodyFor(state))
                        : _bodyFor(state),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Places reaction cameras without stealing phone content width by default.
  Widget _withReactionPip(GameState state, Widget child) {
    Uint8List? peerBytes;
    if (!_useWebRtcMedia &&
        _peerFrameBase64 != null &&
        _av.peerCameraEnabled) {
      try {
        peerBytes = base64Decode(_peerFrameBase64!);
      } catch (_) {}
    }

    final rtc = _webrtc;
    final lan = _lanVideo;
    Widget? peerVideo;
    Widget? localVideo;
    if (rtc != null) {
      peerVideo = RTCVideoView(
        rtc.remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: true,
      );
      localVideo = RTCVideoView(
        rtc.localRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: true,
      );
    } else if (lan != null && lan.mediaReady) {
      peerVideo = RTCVideoView(
        lan.remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: true,
      );
      localVideo = RTCVideoView(
        lan.localRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: true,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = ReactionAvMetrics.forWidth(constraints.maxWidth);
        final layout = _av.audioOnlyLiveMedia
            ? ReactionAvLayout.strip
            : _avLayoutPref.resolve(width: constraints.maxWidth);
        final panel = ReactionAvPanel(
          av: _av,
          layout: layout,
          layoutPref: _avLayoutPref,
          metrics: metrics,
          peerJpeg: peerBytes,
          peerVideo: peerVideo,
          localVideo: localVideo,
          onToggleCamera: _toggleCamera,
          onToggleMic: _toggleMic,
          onCycleLayout: _cycleAvLayout,
        );

        if (layout == ReactionAvLayout.strip) {
          // Content-sized media row — game content keeps the remaining space.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              panel,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bodyConstraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: bodyConstraints.maxHeight,
                        ),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: child,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }

        // Side panel: true split on wide screens, overlay reserve on narrow.
        final wide = constraints.maxWidth >= 700;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: child),
              panel,
            ],
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  right: metrics.sideReserveWidth(layout),
                ),
                child: child,
              ),
            ),
            Align(alignment: Alignment.topRight, child: panel),
          ],
        );
      },
    );
  }

  Widget _bodyFor(GameState state) {
    switch (state.phase) {
      case GamePhase.selecting:
      case GamePhase.waitingForOpponent:
        return _selectPhase(state);
      case GamePhase.reveal:
        return _revealPhase(state);
      case GamePhase.reaction:
        return _reactionPhase(state);
      case GamePhase.roundResult:
        return _roundResult(state);
      case GamePhase.gameOver:
        return _gameOver(state);
      case GamePhase.disconnected:
        return _disconnectedPhase(state);
      case GamePhase.lobby:
        return _centeredMessage('Returning to lobby…');
    }
  }

  Widget _centeredMessage(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          msg,
          style: BlushTheme.body(16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _tieBreakerBanner(GameState state) {
    if (!state.isTieBreaker) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Text(
        'Tie-breaker — no point until you both agree on who wins.',
        textAlign: TextAlign.center,
        style: BlushTheme.body(
          13,
          weight: FontWeight.w600,
          color: BlushTheme.roseDeep,
        ),
      ),
    );
  }

  Widget _selectPhase(GameState state) {
    final dryGuest = widget.controller.dryRunAwaitingGuestSubmit;
    // Both seats must still be able to submit while the other is already waiting.
    // Phase flips to waitingForOpponent after the *first* submission — do not
    // treat that as "selection locked" for the player who has not submitted yet.
    final canSelect = widget.controller.dryRun
        ? true
        : !state.localHasSubmitted &&
            (state.phase == GamePhase.selecting ||
                state.phase == GamePhase.waitingForOpponent);

    final dryHint = dryGuest
        ? 'Pick a card for ${state.guest.name}'
        : (widget.controller.dryRun && state.hostSubmittedChoiceId == null
            ? 'Pick a card for ${state.host.name}'
            : null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 700;
        final statement = CardFace(
          text: state.statementText ?? '',
          isStatement: true,
        );

        final hand = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tieBreakerBanner(state),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                dryHint ??
                    (state.localHasSubmitted && !widget.controller.dryRun
                        ? 'Waiting for your partner…'
                        : state.isTieBreaker
                            ? 'Pick again for the tie-breaker'
                            : 'Choose your most blush-worthy answer'),
                style: BlushTheme.body(14, color: BlushTheme.inkMuted),
              ),
            ),
            const SizedBox(height: 10),
            HandStrip(
              choiceIds: widget.controller.activeHand,
              resolve: widget.controller.choice,
              selectedId: _selectedChoiceId,
              enabled: canSelect,
              onSelect: (id) => setState(() => _selectedChoiceId = id),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                onPressed: !canSelect || _selectedChoiceId == null
                    ? null
                    : () async {
                        final id = _selectedChoiceId!;
                        setState(() => _selectedChoiceId = null);
                        await widget.controller.submitChoice(id);
                      },
                child: const Text('Submit face-down'),
              ),
            ),
          ],
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: statement,
                ),
              ),
              Expanded(child: hand),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: statement,
            ),
            const SizedBox(height: 12),
            hand,
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _revealPhase(GameState state) {
    final hostFilled = widget.controller
            .statement(state.statementId!)
            ?.fillWith(state.hostSubmittedChoiceText ?? '') ??
        '';
    final guestFilled = widget.controller
            .statement(state.statementId!)
            ?.fillWith(state.guestSubmittedChoiceText ?? '') ??
        '';

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _tieBreakerBanner(state),
        Text(
          'Read aloud, then look into each other\'s eyes.',
          style: BlushTheme.body(14, color: BlushTheme.inkMuted),
        ),
        const SizedBox(height: 16),
        Text(
          state.host.name,
          style: BlushTheme.body(13, weight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        CardFace(text: hostFilled, isStatement: true),
        const SizedBox(height: 20),
        Text(
          state.guest.name,
          style: BlushTheme.body(13, weight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        CardFace(text: guestFilled, isStatement: true),
        const SizedBox(height: 24),
        ShareButton(
          outlined: true,
          label: 'Share lines',
          onPressed: () {
            _share.shareText(
              'Blushcraft reveal\n'
              '${state.host.name}: $hostFilled\n'
              '${state.guest.name}: $guestFilled',
              subject: 'Blushcraft combo',
            );
          },
        ),
        const SizedBox(height: 12),
        if (widget.controller.isHost || widget.controller.dryRun)
          ElevatedButton(
            onPressed: () => widget.controller.continueToReaction(),
            child: const Text('Reaction check'),
          )
        else
          Text(
            'Waiting for host to start the reaction check…',
            textAlign: TextAlign.center,
            style: BlushTheme.body(14, color: BlushTheme.inkMuted),
          ),
      ],
    );
  }

  Widget _disconnectedPhase(GameState state) {
    final local = _local;
    final discovered = local?.discovered.entries.toList() ?? [];
    final isHost = widget.controller.isHost;

    return ListenableBuilder(
      listenable: widget.session ?? widget.controller,
      builder: (context, _) {
        final hosts = local?.discovered.entries.toList() ?? discovered;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.wifi_off, size: 48, color: BlushTheme.roseDeep),
            const SizedBox(height: 16),
            Text(
              'Connection paused',
              style: BlushTheme.display(28),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              state.message ??
                  'Your game is saved on this device. Reconnect to continue.',
              style: BlushTheme.body(15, color: BlushTheme.inkMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              widget.session?.status ?? '',
              style: BlushTheme.body(13, color: BlushTheme.inkMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (local != null && isHost) ...[
              Text(
                'Keep this screen open. Your partner should Join again and tap Connect.',
                style: BlushTheme.body(14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => local.ensureHostingForReconnect(),
                child: const Text('Re-advertise as host'),
              ),
            ] else if (local != null) ...[
              Text(
                'Find the host again, then Connect to resume.',
                style: BlushTheme.body(14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => local.beginReconnectDiscovery(),
                child: const Text('Search again'),
              ),
              const SizedBox(height: 16),
              ...hosts.map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  trailing: ElevatedButton(
                    onPressed: () => local.connectTo(e.key),
                    child: const Text('Connect'),
                  ),
                ),
              ),
            ] else ...[
              Text(
                'For online WebRTC games, leave and create a new QR invite to reconnect.',
                style: BlushTheme.body(14),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 28),
            TextButton(
              onPressed: widget.onLeave,
              child: const Text('Leave game'),
            ),
          ],
        );
      },
    );
  }

  Widget _reactionPhase(GameState state) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _tieBreakerBanner(state),
        Text(
          state.message ?? 'Who broke first?',
          style: BlushTheme.body(15, color: BlushTheme.inkMuted),
        ),
        const SizedBox(height: 8),
        Text(
          'Watch your partner in the preview; genuine reactions count.',
          style: BlushTheme.body(13, color: BlushTheme.inkMuted),
        ),
        const SizedBox(height: 20),
        Text(
          widget.controller.dryRunAwaitingGuestVote
              ? 'Confirm as ${state.guest.name}'
              : 'Tap who gets the point (the one who did NOT blush first)',
          style: BlushTheme.body(14, weight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => widget.controller.voteReactionWinner(state.host.id),
          child: Text('${state.host.name} wins the round'),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () => widget.controller.voteReactionWinner(state.guest.id),
          style: ElevatedButton.styleFrom(backgroundColor: BlushTheme.roseDeep),
          child: Text('${state.guest.name} wins the round'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: !_av.cameraEnabled
              ? null
              : () async {
                  final b64 = await _av.captureBase64Jpeg();
                  if (b64 == null) return;
                  await _share.shareImageBytes(
                    base64Decode(b64),
                    text: 'Caught mid-blush: Blushcraft',
                  );
                },
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Capture & share selfie'),
        ),
      ],
    );
  }

  Widget _roundResult(GameState state) {
    final combo = state.lastCombo;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.message ?? 'Point awarded',
            style: BlushTheme.display(28),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (combo != null) ...[
            CardFace(text: combo.hostFilled, isStatement: true),
            const SizedBox(height: 10),
            CardFace(text: combo.guestFilled, compact: true),
            const SizedBox(height: 16),
            ShareButton(
              onPressed: () => _share.shareCombo(combo),
              label: 'Share combo',
            ),
          ],
          const SizedBox(height: 24),
          if (widget.controller.isHost || widget.controller.dryRun)
            ElevatedButton(
              onPressed: () => widget.controller.nextRound(),
              child: const Text('Next round'),
            )
          else
            Text(
              'Waiting for host…',
              textAlign: TextAlign.center,
              style: BlushTheme.body(14, color: BlushTheme.inkMuted),
            ),
        ],
      ),
    );
  }

  Widget _gameOver(GameState state) {
    final winner =
        state.host.score >= state.pointsToWin ? state.host : state.guest;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '${winner.name} wins!',
          style: BlushTheme.display(36, color: BlushTheme.roseDeep),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '${state.host.name} ${state.host.score} - ${state.guest.score} ${state.guest.name}',
          textAlign: TextAlign.center,
          style: BlushTheme.body(18),
        ),
        const SizedBox(height: 28),
        Text('Choose a prize', style: BlushTheme.display(22)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _prizePresets.map((p) {
            final selected = state.prize == p;
            return ChoiceChip(
              label: Text(p),
              selected: selected,
              onSelected: (_) => widget.controller.setPrize(p),
              selectedColor: BlushTheme.blush,
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _prizeController,
          decoration: const InputDecoration(
            labelText: 'Or type your own prize',
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) widget.controller.setPrize(v.trim());
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            final v = _prizeController.text.trim();
            if (v.isNotEmpty) widget.controller.setPrize(v);
          },
          child: const Text('Set custom prize'),
        ),
        if (state.prize != null) ...[
          const SizedBox(height: 16),
          Text(
            'Prize: ${state.prize}',
            style: BlushTheme.body(
              16,
              weight: FontWeight.w600,
              color: BlushTheme.roseDeep,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 28),
        ShareButton(
          onPressed: () => _share.shareGameResult(state),
          label: 'Share results',
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: widget.onLeave,
          child: const Text('Back to home'),
        ),
      ],
    );
  }
}
