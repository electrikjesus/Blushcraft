import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../util/blush_log.dart';
import '../game_message.dart';
import 'ice_config.dart';

/// Video-only WebRTC bridge for Local LAN play.
///
/// Game sync + Opus/AAC audio stay on the WebSocket. This peer connection
/// carries camera tracks only (getUserMedia audio is off to avoid fighting
/// [AudioRecorder]).
class LanWebrtcVideo extends ChangeNotifier {
  LanWebrtcVideo({
    required this.isHost,
    required this.send,
  });

  final bool isHost;
  final Future<void> Function(GameMessage message) send;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStreamTrack? _videoTrack;
  bool _renderersReady = false;
  bool _starting = false;
  bool _offerInFlight = false;
  bool _remoteSet = false;
  final _pendingIce = <RTCIceCandidate>[];

  bool mediaReady = false;
  bool pcConnected = false;
  String? lastError;

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  /// Start (or keep) the video PC when both sides want live video.
  Future<void> ensureStarted() async {
    if (_pc != null || _starting) return;
    _starting = true;
    lastError = null;
    try {
      await _ensureRenderers();
      final pc = await createPeerConnection(IceConfig.peerConnectionConfig());
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null || candidate.candidate!.isEmpty) {
          return;
        }
        unawaited(
          send(
            WebrtcVideoSignalMessage(
              op: 'ice',
              candidate: candidate.candidate,
              sdpMid: candidate.sdpMid,
              sdpMLineIndex: candidate.sdpMLineIndex,
            ),
          ),
        );
      };
      pc.onConnectionState = (state) {
        blushLog('LanRTC', 'pcState=$state');
        pcConnected =
            state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          lastError = 'LAN video peer failed';
        }
        notifyListeners();
      };
      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams[0];
          mediaReady = true;
          blushLog('LanRTC', 'remote video track received');
          notifyListeners();
        }
      };
      _pc = pc;
      await _attachLocalVideo(pc);
      if (isHost) {
        await _sendOffer();
      } else {
        blushLog('LanRTC', 'guest waiting for offer');
      }
    } catch (e) {
      lastError = '$e';
      blushLog('LanRTC', 'ensureStarted failed: $e');
      notifyListeners();
    } finally {
      _starting = false;
    }
  }

  Future<void> _attachLocalVideo(RTCPeerConnection pc) async {
    if (_localStream != null) return;
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': 320,
          'height': 240,
        },
      });
      _localStream = stream;
      localRenderer.srcObject = stream;
      final tracks = stream.getVideoTracks();
      if (tracks.isEmpty) {
        blushLog('LanRTC', 'getUserMedia returned no video tracks');
        return;
      }
      _videoTrack = tracks.first;
      _videoTrack!.enabled = false;
      await pc.addTrack(_videoTrack!, stream);
      mediaReady = true;
      blushLog('LanRTC', 'local video track attached (disabled until toggle)');
      notifyListeners();
    } catch (e) {
      lastError = 'Camera unavailable for LAN video: $e';
      blushLog('LanRTC', 'getUserMedia video failed: $e');
      notifyListeners();
    }
  }

  Future<void> _sendOffer() async {
    final pc = _pc;
    if (pc == null || _offerInFlight) return;
    _offerInFlight = true;
    try {
      final offer = await pc.createOffer({
        'offerToReceiveAudio': 0,
        'offerToReceiveVideo': 1,
      });
      await pc.setLocalDescription(offer);
      final local = await pc.getLocalDescription();
      final sdp = local?.sdp ?? offer.sdp ?? '';
      blushLog('LanRTC', 'sending offer sdpBytes=${sdp.length}');
      await send(WebrtcVideoSignalMessage(op: 'offer', sdp: sdp));
    } catch (e) {
      blushLog('LanRTC', 'offer failed: $e');
      lastError = '$e';
      notifyListeners();
    } finally {
      _offerInFlight = false;
    }
  }

  Future<void> setLocalVideoEnabled(bool enabled) async {
    final track = _videoTrack;
    if (track == null) {
      if (enabled && _pc != null) {
        await _attachLocalVideo(_pc!);
        _videoTrack?.enabled = enabled;
      }
      return;
    }
    if (track.enabled == enabled) return;
    track.enabled = enabled;
    blushLog('LanRTC', 'local video enabled=$enabled');
    notifyListeners();
  }

  Future<void> handleSignal(WebrtcVideoSignalMessage msg) async {
    blushLog('LanRTC', 'signal op=${msg.op}');
    if (msg.op == 'offer') {
      if (isHost) return;
      await ensureStarted();
      final pc = _pc;
      final sdp = msg.sdp;
      if (pc == null || sdp == null || sdp.isEmpty) return;
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      _remoteSet = true;
      await _drainPendingIce();
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': 0,
        'offerToReceiveVideo': 1,
      });
      await pc.setLocalDescription(answer);
      final local = await pc.getLocalDescription();
      final out = local?.sdp ?? answer.sdp ?? '';
      blushLog('LanRTC', 'sending answer sdpBytes=${out.length}');
      await send(WebrtcVideoSignalMessage(op: 'answer', sdp: out));
      return;
    }
    if (msg.op == 'answer') {
      if (!isHost) return;
      final pc = _pc;
      final sdp = msg.sdp;
      if (pc == null || sdp == null || sdp.isEmpty) return;
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      _remoteSet = true;
      await _drainPendingIce();
      blushLog('LanRTC', 'host applied answer');
      return;
    }
    if (msg.op == 'ice') {
      final cand = msg.candidate;
      if (cand == null || cand.isEmpty) return;
      final ice = RTCIceCandidate(cand, msg.sdpMid, msg.sdpMLineIndex);
      if (!_remoteSet || _pc == null) {
        _pendingIce.add(ice);
        return;
      }
      try {
        await _pc!.addCandidate(ice);
      } catch (e) {
        blushLog('LanRTC', 'addCandidate failed: $e');
      }
      return;
    }
    if (msg.op == 'bye') {
      await _teardown();
      return;
    }
    blushLog('LanRTC', 'unknown op=${msg.op}');
  }

  Future<void> _drainPendingIce() async {
    final pc = _pc;
    if (pc == null) return;
    final pending = List<RTCIceCandidate>.from(_pendingIce);
    _pendingIce.clear();
    for (final ice in pending) {
      try {
        await pc.addCandidate(ice);
      } catch (e) {
        blushLog('LanRTC', 'drain ice failed: $e');
      }
    }
  }

  Future<void> stop() async {
    blushLog('LanRTC', 'stop');
    try {
      await send(const WebrtcVideoSignalMessage(op: 'bye'));
    } catch (_) {}
    await _teardown();
  }

  Future<void> _teardown() async {
    _pendingIce.clear();
    _remoteSet = false;
    _offerInFlight = false;
    pcConnected = false;
    mediaReady = false;
    _videoTrack = null;
    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final t in stream.getTracks()) {
        await t.stop();
      }
    }
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    final pc = _pc;
    _pc = null;
    try {
      await pc?.close();
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_teardown());
    unawaited(localRenderer.dispose());
    unawaited(remoteRenderer.dispose());
    super.dispose();
  }
}
