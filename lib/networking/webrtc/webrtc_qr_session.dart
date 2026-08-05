import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import '../game_message.dart';
import '../game_transport.dart';
import 'ice_config.dart';
import 'sdp_qr_codec.dart';

/// WebRTC session paired via QR / paste (no signaling server).
class WebRtcQrSession extends GameSession {
  WebRtcQrSession({
    required this.userName,
    required this.onMessage,
    this.onConnection,
  });

  final String userName;
  final MessageHandler onMessage;
  final ConnectionHandler? onConnection;

  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;
  final _ice = <RTCIceCandidate>[];
  final _uuid = const Uuid();

  String? sessionId;
  String? offerPayload;
  String? answerPayload;
  bool _isHost = false;
  bool _hadConnection = false;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  bool mediaReady = false;

  @override
  String? status;

  @override
  bool get isConnected =>
      _channel?.state == RTCDataChannelState.RTCDataChannelOpen;

  bool get isHostRole => _isHost;

  Future<void> _ensureRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<RTCPeerConnection> _createPc() async {
    await _ensureRenderers();
    final pc = await createPeerConnection(IceConfig.peerConnectionConfig());
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        _ice.add(candidate);
      }
    };
    pc.onIceGatheringState = (state) {
      debugPrint('ICE gathering: $state');
    };
    pc.onConnectionState = (state) {
      debugPrint('PC state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (isConnected || _hadConnection) {
          _handleDisconnect();
        }
      }
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        mediaReady = true;
        notifyListeners();
      }
    };
    pc.onDataChannel = (channel) {
      _bindChannel(channel);
    };
    _pc = pc;
    return pc;
  }

  Future<void> _attachLocalMedia(RTCPeerConnection pc) async {
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': 320,
          'height': 240,
        },
      });
      _localStream = stream;
      localRenderer.srcObject = stream;
      for (final track in stream.getTracks()) {
        // Opt-in: stay muted until the in-app consent toggle enables them.
        track.enabled = false;
        await pc.addTrack(track, stream);
      }
      mediaReady = true;
      notifyListeners();
    } catch (e) {
      debugPrint('getUserMedia failed (continuing data-only): $e');
      status = 'Camera/mic unavailable; game sync still works';
      notifyListeners();
    }
  }

  void _bindChannel(RTCDataChannel channel) {
    _channel = channel;
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        final wasReconnect = _hadConnection;
        _hadConnection = true;
        status = wasReconnect ? 'Reconnected' : 'Connected';
        onConnection?.call(
          connected: true,
          endpointId: sessionId,
          endpointName: userName,
          isReconnect: wasReconnect,
        );
        notifyListeners();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _handleDisconnect();
      }
    };
    channel.onMessage = (message) async {
      try {
        if (message.isBinary) return;
        final raw = message.text;
        if (raw.isEmpty) return;
        final msg = GameMessage.decode(raw);
        await onMessage(msg);
      } catch (e) {
        debugPrint('WebRTC message decode error: $e');
      }
    };
  }

  void _handleDisconnect() {
    status = 'Partner disconnected';
    onConnection?.call(connected: false, isReconnect: false);
    notifyListeners();
  }

  Future<void> _waitForIce(RTCPeerConnection pc, {Duration timeout = const Duration(seconds: 4)}) async {
    final done = Completer<void>();
    void check(RTCIceGatheringState? state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !done.isCompleted) {
        done.complete();
      }
    }

    pc.onIceGatheringState = check;
    check(pc.iceGatheringState);
    await Future.any([
      done.future,
      Future<void>.delayed(timeout),
    ]);
  }

  List<String> _serializeIce() {
    return _ice
        .where((c) => c.candidate != null && c.candidate!.isNotEmpty)
        .map(
          (c) => jsonEncode({
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          }),
        )
        .toList();
  }

  Future<void> _applyRemoteIce(List<dynamic>? ice) async {
    final pc = _pc;
    if (pc == null || ice == null) return;
    for (final item in ice) {
      try {
        final map = item is String
            ? jsonDecode(item) as Map<String, dynamic>
            : item as Map<String, dynamic>;
        await pc.addCandidate(
          RTCIceCandidate(
            map['candidate'] as String?,
            map['sdpMid'] as String?,
            map['sdpMLineIndex'] as int?,
          ),
        );
      } catch (e) {
        debugPrint('ICE add failed: $e');
      }
    }
  }

  /// Host: build offer payload for QR / share.
  Future<String> startAsHost() async {
    _isHost = true;
    sessionId = _uuid.v4();
    _ice.clear();
    status = 'Creating invite…';
    notifyListeners();

    final pc = await _createPc();
    await _attachLocalMedia(pc);

    final channel = await pc.createDataChannel(
      'blushcraft',
      RTCDataChannelInit()..ordered = true,
    );
    _bindChannel(channel);

    final offer = await pc.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });
    await pc.setLocalDescription(offer);
    await _waitForIce(pc);

    final local = await pc.getLocalDescription();
    offerPayload = SdpQrCodec.encodeEnvelope(
      role: 'offer',
      sessionId: sessionId!,
      displayName: userName,
      sdp: local?.sdp ?? offer.sdp ?? '',
      ice: _serializeIce(),
    );
    status = 'Show this QR to your partner (best on Wi-Fi)';
    notifyListeners();
    return offerPayload!;
  }

  /// Guest: consume host offer, return answer payload for host to scan.
  Future<String> acceptOfferAndCreateAnswer(String rawOffer) async {
    _isHost = false;
    _ice.clear();
    status = 'Joining…';
    notifyListeners();

    final envelope = SdpQrCodec.decodeEnvelope(rawOffer);
    if (envelope['role'] != 'offer') {
      throw const FormatException('Expected a host offer QR');
    }
    sessionId = envelope['session'] as String?;

    final pc = await _createPc();
    await _attachLocalMedia(pc);

    await pc.setRemoteDescription(
      RTCSessionDescription(envelope['sdp'] as String, 'offer'),
    );
    await _applyRemoteIce(envelope['ice'] as List<dynamic>?);

    final answer = await pc.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });
    await pc.setLocalDescription(answer);
    await _waitForIce(pc);

    final local = await pc.getLocalDescription();
    answerPayload = SdpQrCodec.encodeEnvelope(
      role: 'answer',
      sessionId: sessionId ?? _uuid.v4(),
      displayName: userName,
      sdp: local?.sdp ?? answer.sdp ?? '',
      ice: _serializeIce(),
    );
    status = 'Show this answer QR to the host';
    notifyListeners();
    return answerPayload!;
  }

  /// Host: apply guest answer from QR / paste.
  Future<void> acceptAnswer(String rawAnswer) async {
    final pc = _pc;
    if (pc == null) {
      throw StateError('Start hosting before accepting an answer');
    }
    final envelope = SdpQrCodec.decodeEnvelope(rawAnswer);
    if (envelope['role'] != 'answer') {
      throw const FormatException('Expected a guest answer QR');
    }
    if (sessionId != null &&
        envelope['session'] != null &&
        envelope['session'] != sessionId) {
      throw const FormatException('Answer session does not match this invite');
    }

    await pc.setRemoteDescription(
      RTCSessionDescription(envelope['sdp'] as String, 'answer'),
    );
    await _applyRemoteIce(envelope['ice'] as List<dynamic>?);
    status = 'Connecting…';
    notifyListeners();
  }

  Future<void> setTrackEnabled({required bool video, required bool audio}) async {
    final stream = _localStream;
    if (stream == null) return;
    for (final t in stream.getVideoTracks()) {
      t.enabled = video;
    }
    for (final t in stream.getAudioTracks()) {
      t.enabled = audio;
    }
    notifyListeners();
  }

  @override
  Future<void> send(GameMessage message) async {
    final ch = _channel;
    if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    await ch.send(RTCDataChannelMessage(message.encode()));
  }

  @override
  Future<void> stopAll() async {
    try {
      await _channel?.close();
    } catch (_) {}
    _channel = null;
    try {
      for (final t in _localStream?.getTracks() ?? []) {
        await t.stop();
      }
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    offerPayload = null;
    answerPayload = null;
    status = null;
    mediaReady = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stopAll());
    unawaited(localRenderer.dispose());
    unawaited(remoteRenderer.dispose());
    super.dispose();
  }
}
