import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../camera/reaction_camera.dart';
import '../../networking/game_message.dart';
import '../../networking/game_transport.dart';
import '../../networking/webrtc/webrtc_qr_session.dart';
import '../av_consent.dart';
import '../theme.dart';

/// Optional reaction camera/mic setup for the lobby (same consent as in-game).
class LobbyAvSetup extends StatefulWidget {
  const LobbyAvSetup({
    super.key,
    required this.localPlayerId,
    this.session,
  });

  final String localPlayerId;
  final GameSession? session;

  @override
  State<LobbyAvSetup> createState() => _LobbyAvSetupState();
}

class _LobbyAvSetupState extends State<LobbyAvSetup> {
  final _av = ReactionAvController();
  bool _consentGiven = false;
  bool _busy = false;

  WebRtcQrSession? get _webrtc =>
      widget.session is WebRtcQrSession ? widget.session as WebRtcQrSession : null;

  @override
  void initState() {
    super.initState();
    _av.addListener(_onAv);
    _webrtc?.addListener(_onAv);
    unawaited(_restore());
  }

  Future<void> _restore() async {
    _consentGiven = await loadAvConsentGiven();
    final wants = await loadAvWantFlags();
    if (!mounted) return;
    if (wants.camera || wants.mic) {
      if (!_consentGiven) return;
      setState(() => _busy = true);
      if (wants.camera && _webrtc == null) {
        await _av.init();
      }
      if (wants.camera) await _av.setCameraEnabled(true);
      if (wants.mic) await _av.setMicEnabled(true);
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
      ),
    );
  }

  Future<void> _persistWants() async {
    await saveAvWantFlags(
      camera: _av.cameraEnabled,
      mic: _av.micEnabled,
    );
  }

  Future<void> _toggleCamera() async {
    if (_busy) return;
    if (_av.cameraEnabled) {
      await _av.setCameraEnabled(false);
    } else {
      if (!_consentGiven) {
        final ok = await showAvConsentSheet(context);
        if (!ok || !mounted) return;
        _consentGiven = true;
      }
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
      if (!_consentGiven) {
        final ok = await showAvConsentSheet(context);
        if (!ok || !mounted) return;
        _consentGiven = true;
      }
      await _av.setMicEnabled(true);
    }
    await _syncTransport();
    await _persistWants();
  }

  @override
  void dispose() {
    _av.removeListener(_onAv);
    _webrtc?.removeListener(_onAv);
    _av.dispose();
    super.dispose();
  }

  Widget _preview() {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Reaction camera', style: BlushTheme.display(18)),
        const SizedBox(height: 6),
        Text(
          'Optional. Set this up before the match so you are ready for the '
          'reaction check. Your partner only sees or hears you after you allow it.',
          style: BlushTheme.body(13, color: BlushTheme.inkMuted),
        ),
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
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _toggleCamera,
                    icon: Icon(
                      _av.cameraEnabled ? Icons.videocam : Icons.videocam_off,
                    ),
                    label: Text(_av.cameraEnabled ? 'Camera on' : 'Camera off'),
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
      ],
    );
  }
}
