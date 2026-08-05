import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../camera/reaction_camera.dart';
import '../../models/game_state.dart';
import '../../networking/game_message.dart';
import '../../networking/nearby_game_session.dart';
import '../../share/share_service.dart';
import '../../state/game_controller.dart';
import 'theme.dart';
import 'widgets/card_face.dart';
import 'widgets/hand_strip.dart';
import 'widgets/reaction_pip.dart';
import 'widgets/score_pips.dart';
import 'widgets/share_button.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    this.session,
    required this.onLeave,
  });

  final GameController controller;
  final NearbyGameSession? session;
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
  DateTime _lastAudioSent = DateTime.fromMillisecondsSinceEpoch(0);

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
    widget.controller.onPeerAudio = (id, b64) async {
      try {
        await _av.playPeerAudio(base64Decode(b64));
      } catch (_) {}
    };
    widget.controller.onAvPrivacy = (id, {required cameraEnabled, required micEnabled}) {
      if (!mounted) return;
      _av.setPeerPrivacy(cameraOn: cameraEnabled, micOn: micEnabled);
      if (!cameraEnabled) {
        setState(() => _peerFrameBase64 = null);
      } else {
        setState(() {});
      }
    };
    _av.onLocalAudioChunk = (bytes) {
      final session = widget.session;
      if (session == null || !session.isConnected) return;
      if (!_av.micEnabled) return;
      final now = DateTime.now();
      // Limit payload rate over Nearby (~4 chunks/sec max).
      if (now.difference(_lastAudioSent).inMilliseconds < 220) return;
      if (bytes.length > 12 * 1024) return;
      _lastAudioSent = now;
      session.send(
        PeerAudioMessage(
          playerId: widget.controller.localPlayerId,
          base64Aac: base64Encode(bytes),
        ),
      );
    };
    _av.addListener(() {
      if (mounted) setState(() {});
    });
    _onGame();
  }

  void _onGame() {
    final phase = widget.controller.state?.phase;
    if (_shouldStreamAv(phase)) {
      _ensureAv();
    } else {
      _stopFrames();
      unawaited(_av.stopMic());
    }
    if (mounted) setState(() {});
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
    final ok = await _av.init();
    if (!ok || !mounted) return;
    _startFrames();
    if (_av.micEnabled) {
      await _av.startMic();
    }
    await _publishPrivacy();
  }

  Future<void> _publishPrivacy() async {
    final session = widget.session;
    if (session == null || !session.isConnected) return;
    await session.send(
      AvPrivacyMessage(
        playerId: widget.controller.localPlayerId,
        cameraEnabled: _av.cameraEnabled,
        micEnabled: _av.micEnabled,
      ),
    );
  }

  void _startFrames() {
    _frameTimer?.cancel();
    // Local preview works without a session; peer frames need Nearby.
    _frameTimer = Timer.periodic(const Duration(milliseconds: 900), (_) async {
      if (!_av.cameraEnabled) return;
      final b64 = await _av.captureBase64Jpeg();
      if (b64 == null) return;
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
    await _av.setCameraEnabled(!_av.cameraEnabled);
    await _publishPrivacy();
    if (_av.cameraEnabled) {
      _startFrames();
    }
  }

  Future<void> _toggleMic() async {
    await _av.setMicEnabled(!_av.micEnabled);
    await _publishPrivacy();
  }

  @override
  void dispose() {
    _stopFrames();
    widget.controller.removeListener(_onGame);
    widget.controller.onPeerFrame = null;
    widget.controller.onPeerAudio = null;
    widget.controller.onAvPrivacy = null;
    _av.onLocalAudioChunk = null;
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
                    : 'Round ${state.roundNumber}',
              ),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onLeave,
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
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
                    child: _shouldStreamAv(state.phase)
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

  /// Keeps statement/hand readable while peer video stays visible all round.
  Widget _withReactionPip(GameState state, Widget child) {
    Uint8List? peerBytes;
    if (_peerFrameBase64 != null && _av.peerCameraEnabled) {
      try {
        peerBytes = base64Decode(_peerFrameBase64!);
      } catch (_) {}
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 700;
        // Reserve a clear lane so the pip never covers statement or hand.
        final edgePad = wide ? 8.0 : ReactionPip.width + 16;

        return Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(right: edgePad),
                child: child,
              ),
            ),
            ReactionPip(
              av: _av,
              peerJpeg: peerBytes,
              onToggleCamera: _toggleCamera,
              onToggleMic: _toggleMic,
              alignment: Alignment.topRight,
            ),
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

  Widget _selectPhase(GameState state) {
    final dryGuest = widget.controller.dryRunAwaitingGuestSubmit;
    final canSelect = widget.controller.dryRun
        ? true
        : (state.phase == GamePhase.selecting && !state.localHasSubmitted);

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                dryHint ??
                    (state.localHasSubmitted && !widget.controller.dryRun
                        ? 'Waiting for your partner…'
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
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: statement,
            ),
            const Spacer(),
            hand,
            const SizedBox(height: 12),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
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
    final session = widget.session;
    final discovered = session?.discovered.entries.toList() ?? [];
    final isHost = widget.controller.isHost;

    return ListenableBuilder(
      listenable: session ?? widget.controller,
      builder: (context, _) {
        final hosts = session?.discovered.entries.toList() ?? discovered;
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
              session?.status ?? '',
              style: BlushTheme.body(13, color: BlushTheme.inkMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (isHost) ...[
              Text(
                'Keep this screen open. Your partner should Join again and tap Connect.',
                style: BlushTheme.body(14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => session?.ensureHostingForReconnect(),
                child: const Text('Re-advertise as host'),
              ),
            ] else ...[
              Text(
                'Find the host again, then Connect to resume.',
                style: BlushTheme.body(14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => session?.beginReconnectDiscovery(),
                child: const Text('Search again'),
              ),
              const SizedBox(height: 16),
              ...hosts.map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  trailing: ElevatedButton(
                    onPressed: () => session?.connectTo(e.key),
                    child: const Text('Connect'),
                  ),
                ),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          state.message ?? 'Who broke first?',
          style: BlushTheme.body(15, color: BlushTheme.inkMuted),
        ),
        const SizedBox(height: 8),
        Text(
          'Watch your partner in the corner; genuine reactions count.',
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
        OutlinedButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Read the lines again: hold eye contact!'),
              ),
            );
          },
          child: const Text('Read again'),
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
          const Spacer(),
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
