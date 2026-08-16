import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../camera/reaction_camera.dart';
import '../../networking/game_message.dart';
import '../../networking/game_transport.dart';
import '../../networking/webrtc/webrtc_qr_session.dart';
import '../../state/game_controller.dart';
import '../../util/camera_availability.dart';
import '../av_consent.dart';
import '../theme.dart';

/// Optional reaction camera/mic + mutual live-media setup for the lobby.
class LobbyAvSetup extends StatefulWidget {
  const LobbyAvSetup({
    super.key,
    required this.localPlayerId,
    required this.controller,
    this.session,
  });

  final String localPlayerId;
  final GameController controller;
  final GameSession? session;

  @override
  State<LobbyAvSetup> createState() => _LobbyAvSetupState();
}

class _LobbyAvSetupState extends State<LobbyAvSetup> {
  final _av = ReactionAvController();
  bool _consentGiven = false;
  bool _busy = false;
  bool _probeDone = false;

  WebRtcQrSession? get _webrtc =>
      widget.session is WebRtcQrSession ? widget.session as WebRtcQrSession : null;

  @override
  void initState() {
    super.initState();
    _av.addListener(_onAv);
    _webrtc?.addListener(_onAv);
    widget.session?.addListener(_onSession);
    widget.controller.onAvPrivacy = _onPeerPrivacy;
    unawaited(_restore());
  }

  void _onPeerPrivacy(
    String playerId, {
    required bool cameraEnabled,
    required bool micEnabled,
    required bool liveViewEnabled,
    required bool hasCamera,
    required double audioLevel,
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
    // Echo so both lobby setups agree after a late toggle.
    if (liveViewEnabled && !peerLiveBefore) {
      unawaited(_syncTransport());
    }
  }

  void _onSession() {
    if (mounted) unawaited(_syncTransport());
  }

  Future<void> _restore() async {
    final hasCam = await deviceHasUsableCamera();
    await _av.setDeviceHasCamera(hasCam);
    _consentGiven = await loadAvConsentGiven();
    final wants = await loadAvWantFlags();
    if (!mounted) return;
    _probeDone = true;
    if (wants.camera || wants.mic || wants.liveView) {
      if (!_consentGiven) {
        setState(() {});
        return;
      }
      setState(() => _busy = true);
      if ((wants.camera || wants.liveView || wants.mic) && _webrtc == null) {
        await _av.init();
      }
      if (wants.camera && hasCam) await _av.setCameraEnabled(true);
      if (wants.mic || (wants.liveView && !hasCam)) {
        await _av.setMicEnabled(true);
      }
      if (wants.liveView) await _av.setLiveViewEnabled(true);
      await _syncTransport();
      if (mounted) setState(() => _busy = false);
    } else {
      setState(() {});
    }
  }

  void _onAv() {
    if (mounted) setState(() {});
  }

  Future<void> _syncTransport() async {
    await _webrtc?.setTrackEnabled(
      video: _av.cameraEnabled,
      audio: _av.micEnabled,
    );
    final session = widget.session;
    if (session == null || !session.isConnected) return;
    await session.send(
      AvPrivacyMessage(
        playerId: widget.localPlayerId,
        cameraEnabled: _av.cameraEnabled,
        micEnabled: _av.micEnabled,
        liveViewEnabled: _av.liveViewEnabled,
        hasCamera: _av.deviceHasCamera,
        audioLevel: _av.localDisplayAudioLevel,
      ),
    );
  }

  Future<void> _persistWants() async {
    await saveAvWantFlags(
      camera: _av.cameraEnabled,
      mic: _av.micEnabled,
      liveView: _av.liveViewEnabled,
    );
  }

  Future<bool> _ensureConsent() async {
    if (_consentGiven) return true;
    final ok = await showAvConsentSheet(context);
    if (!ok || !mounted) return false;
    _consentGiven = true;
    return true;
  }

  Future<void> _toggleCamera() async {
    if (_busy || !_av.deviceHasCamera) return;
    if (_av.cameraEnabled) {
      await _av.setCameraEnabled(false);
    } else {
      if (!await _ensureConsent()) return;
      setState(() => _busy = true);
      if (_webrtc == null) {
        final ready = await _av.init();
        if (!ready || !mounted) {
          setState(() => _busy = false);
          return;
        }
      }
      await _av.setCameraEnabled(true);
      if (mounted) setState(() => _busy = false);
    }
    await _syncTransport();
    await _persistWants();
  }

  Future<void> _toggleMic() async {
    if (_busy) return;
    if (_av.micEnabled) {
      await _av.setMicEnabled(false);
    } else {
      if (!await _ensureConsent()) return;
      if (!_av.initialized && _webrtc == null) {
        setState(() => _busy = true);
        await _av.init();
        if (mounted) setState(() => _busy = false);
      }
      await _av.setMicEnabled(true);
    }
    await _syncTransport();
    await _persistWants();
  }

  Future<void> _toggleLiveView(bool enabled) async {
    if (_busy) return;
    if (enabled) {
      if (!await _ensureConsent()) return;
      setState(() => _busy = true);
      if (!_av.initialized && _webrtc == null) {
        await _av.init();
      }
      // Prefer audio when enabling live media; camera stays optional.
      if (!_av.micEnabled) {
        await _av.setMicEnabled(true);
      }
      // Only auto-enable camera when this device actually has one and mic-only
      // wasn't the point — leave camera off on cameraless tablets.
      if (_av.deviceHasCamera && !_av.cameraEnabled) {
        // Do not force camera — user can turn it on separately.
      }
      await _av.setLiveViewEnabled(true);
      if (mounted) setState(() => _busy = false);
    } else {
      await _av.setLiveViewEnabled(false);
    }
    await _syncTransport();
    await _persistWants();
  }

  @override
  void dispose() {
    if (widget.controller.onAvPrivacy == _onPeerPrivacy) {
      widget.controller.onAvPrivacy = null;
    }
    widget.session?.removeListener(_onSession);
    _av.removeListener(_onAv);
    _webrtc?.removeListener(_onAv);
    _av.dispose();
    super.dispose();
  }

  Widget _preview() {
    if (!_av.deviceHasCamera) {
      return Center(
        child: Text(
          'Audio',
          style: BlushTheme.body(11, color: BlushTheme.inkMuted),
        ),
      );
    }
    final rtc = _webrtc;
    if (rtc != null && _av.cameraEnabled) {
      return RTCVideoView(
        rtc.localRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: true,
      );
    }
    if (_av.showPreview && _av.controller != null) {
      return CameraPreview(_av.controller!);
    }
    return Center(
      child: Text(
        _av.cameraEnabled ? '…' : 'Cam off',
        style: BlushTheme.body(11, color: BlushTheme.inkMuted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peerLive = _av.peerLiveViewEnabled;
    final both = _av.bothLiveViewEnabled;
    final audioOnly = both && (!_av.deviceHasCamera || !_av.peerHasCamera);
    final mediaHint = !_probeDone
        ? 'Checking this device…'
        : audioOnly
            ? 'Both ready — audio-only live media during play '
                '(one of you has no camera).'
            : both
                ? 'Both ready — the media row will show during play.'
                : _av.liveViewEnabled
                    ? (peerLive
                        ? 'Ready.'
                        : 'Waiting for your partner to enable live media…')
                    : peerLive
                        ? 'Your partner is ready — enable to show the media row.'
                        : 'Needs both of you. Off by default. '
                            'Works as audio-only if either of you has no camera.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Reaction media', style: BlushTheme.display(18)),
        const SizedBox(height: 6),
        Text(
          'Optional. Turn on mic and/or camera for reactions. '
          'Live media only appears in-game when you both enable it below.',
          style: BlushTheme.body(13, color: BlushTheme.inkMuted),
        ),
        if (_probeDone && !_av.deviceHasCamera) ...[
          const SizedBox(height: 8),
          Text(
            'This device has no usable camera — live media will be audio-only.',
            style: BlushTheme.body(12, color: BlushTheme.roseDeep),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 72,
              height: 96,
              decoration: BoxDecoration(
                color: BlushTheme.creamDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: BlushTheme.creamDark),
              ),
              clipBehavior: Clip.antiAlias,
              child: _preview(),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_av.deviceHasCamera)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _toggleCamera,
                      icon: Icon(
                        _av.cameraEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                      ),
                      label: Text(
                        _av.cameraEnabled ? 'Camera on' : 'Camera off',
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.videocam_off),
                      label: const Text('No camera'),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _toggleMic,
                    icon: Icon(_av.micEnabled ? Icons.mic : Icons.mic_off),
                    label: Text(_av.micEnabled ? 'Mic on' : 'Mic off'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Show live media',
            style: BlushTheme.body(15, weight: FontWeight.w600),
          ),
          subtitle: Text(
            mediaHint,
            style: BlushTheme.body(12, color: BlushTheme.inkMuted),
          ),
          value: _av.liveViewEnabled,
          activeThumbColor: BlushTheme.roseDeep,
          onChanged: _busy || widget.session?.isConnected != true
              ? null
              : _toggleLiveView,
        ),
      ],
    );
  }
}
