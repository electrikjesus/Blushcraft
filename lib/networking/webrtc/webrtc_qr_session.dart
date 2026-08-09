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
///
/// Pairing uses a **data-channel-only** offer/answer so invite strings stay
/// short and scannable. Camera/mic tracks are attached after the channel opens
/// and upgraded over the data channel.
class WebRtcQrSession extends GameSession {
  WebRtcQrSession({
    required this.userName,
    required this.onMessage,
    this.onConnection,
  });

  static const _rtcControlPrefix = '__bc_rtc__:';

  final String userName;
  final MessageHandler onMessage;
  final ConnectionHandler? onConnection;

  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;
  final _ice = <RTCIceCandidate>[];
  final _uuid = const Uuid();
  Timer? _connectTimer;
  bool _mediaUpgradeStarted = false;
  bool _handlingRtcControl = false;

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

  /// Last pairing / connection error for UI (cleared on progress).
  String? lastError;

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
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        lastError =
            'Connection failed. Stay on the same Wi‑Fi when possible '
            '(online play is STUN-only for now).';
        status = lastError;
        _connectTimer?.cancel();
        notifyListeners();
        if (_hadConnection) {
          _handleDisconnect();
        }
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (isConnected || _hadConnection) {
          _handleDisconnect();
        }
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        lastError = null;
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
    if (_localStream != null) return;
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
        _connectTimer?.cancel();
        lastError = null;
        status = wasReconnect ? 'Reconnected' : 'Connected';
        onConnection?.call(
          connected: true,
          endpointId: sessionId,
          endpointName: userName,
          isReconnect: wasReconnect,
        );
        notifyListeners();
        unawaited(_upgradeMediaAfterConnect());
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _handleDisconnect();
      }
    };
    channel.onMessage = (message) async {
      try {
        if (message.isBinary) return;
        final raw = message.text;
        if (raw.isEmpty) return;
        if (raw.startsWith(_rtcControlPrefix)) {
          await _handleRtcControl(raw.substring(_rtcControlPrefix.length));
          return;
        }
        final msg = GameMessage.decode(raw);
        await onMessage(msg);
      } catch (e) {
        debugPrint('WebRTC message decode error: $e');
      }
    };
  }

  Future<void> _sendRtcControl(Map<String, dynamic> body) async {
    final ch = _channel;
    if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    await ch.send(RTCDataChannelMessage('$_rtcControlPrefix${jsonEncode(body)}'));
  }

  Future<void> _upgradeMediaAfterConnect() async {
    if (_mediaUpgradeStarted) return;
    _mediaUpgradeStarted = true;
    final pc = _pc;
    if (pc == null) return;

    await _attachLocalMedia(pc);
    // Only the host drives renegotiation so both sides share one offer/answer.
    if (!_isHost) return;

    try {
      _ice.clear();
      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1,
      });
      await pc.setLocalDescription(offer);
      await _waitForIce(pc, timeout: const Duration(seconds: 8));
      final local = await pc.getLocalDescription();
      await _sendRtcControl({
        'op': 'upgrade_offer',
        'sdp': local?.sdp ?? offer.sdp ?? '',
        'ice': _serializeIce(),
      });
    } catch (e) {
      debugPrint('Media upgrade offer failed: $e');
    }
  }

  Future<void> _handleRtcControl(String jsonBody) async {
    if (_handlingRtcControl) return;
    _handlingRtcControl = true;
    try {
      final map = jsonDecode(jsonBody) as Map<String, dynamic>;
      final op = map['op'] as String?;
      final pc = _pc;
      if (pc == null || op == null) return;

      if (op == 'upgrade_offer' && !_isHost) {
        await _attachLocalMedia(pc);
        await pc.setRemoteDescription(
          RTCSessionDescription(map['sdp'] as String, 'offer'),
        );
        await _applyRemoteIce(map['ice'] as List<dynamic>?);
        _ice.clear();
        final answer = await pc.createAnswer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': 1,
        });
        await pc.setLocalDescription(answer);
        await _waitForIce(pc, timeout: const Duration(seconds: 8));
        final local = await pc.getLocalDescription();
        await _sendRtcControl({
          'op': 'upgrade_answer',
          'sdp': local?.sdp ?? answer.sdp ?? '',
          'ice': _serializeIce(),
        });
      } else if (op == 'upgrade_answer' && _isHost) {
        await pc.setRemoteDescription(
          RTCSessionDescription(map['sdp'] as String, 'answer'),
        );
        await _applyRemoteIce(map['ice'] as List<dynamic>?);
      }
    } catch (e) {
      debugPrint('RTC control failed: $e');
    } finally {
      _handlingRtcControl = false;
    }
  }

  void _handleDisconnect() {
    _connectTimer?.cancel();
    status = 'Partner disconnected';
    onConnection?.call(connected: false, isReconnect: false);
    notifyListeners();
  }

  Future<void> _waitForIce(
    RTCPeerConnection pc, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
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

  /// Keep a small set of host/srflx candidates to shrink QR payloads.
  List<String> _serializeIce() {
    final byType = <String, List<RTCIceCandidate>>{
      'host': [],
      'srflx': [],
      'relay': [],
      'other': [],
    };
    for (final c in _ice) {
      final raw = c.candidate;
      if (raw == null || raw.isEmpty) continue;
      if (raw.contains('typ host')) {
        byType['host']!.add(c);
      } else if (raw.contains('typ srflx')) {
        byType['srflx']!.add(c);
      } else if (raw.contains('typ relay')) {
        byType['relay']!.add(c);
      } else {
        byType['other']!.add(c);
      }
    }

    final picked = <RTCIceCandidate>[
      ...byType['host']!.take(4),
      ...byType['srflx']!.take(3),
      ...byType['relay']!.take(1),
    ];
    if (picked.isEmpty) {
      picked.addAll(_ice.take(6));
    }

    return picked
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

  void _armConnectTimeout() {
    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(seconds: 30), () {
      if (isConnected) return;
      lastError =
          'Still connecting… Prefer Local on the same Wi‑Fi. '
          'For Online, stay on Wi‑Fi, paste a fresh full answer, and try again.';
      status = lastError;
      notifyListeners();
    });
  }

  /// Host: build a short data-channel invite for QR / share.
  Future<String> startAsHost() async {
    _isHost = true;
    _mediaUpgradeStarted = false;
    sessionId = _uuid.v4();
    _ice.clear();
    lastError = null;
    status = 'Creating invite…';
    notifyListeners();

    final pc = await _createPc();
    // Data-channel only for pairing — keeps the QR short.

    final channel = await pc.createDataChannel(
      'blushcraft',
      RTCDataChannelInit()..ordered = true,
    );
    _bindChannel(channel);

    final offer = await pc.createOffer({});
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
    status = 'Show this QR to your partner (best on Wi‑Fi)';
    notifyListeners();
    return offerPayload!;
  }

  /// Guest: consume host offer, return answer payload for host to scan.
  Future<String> acceptOfferAndCreateAnswer(String rawOffer) async {
    _isHost = false;
    _mediaUpgradeStarted = false;
    _ice.clear();
    lastError = null;
    status = 'Joining…';
    notifyListeners();

    try {
      final envelope = SdpQrCodec.decodeEnvelope(rawOffer);
      if (envelope['role'] != 'offer') {
        throw const FormatException('Expected a host offer (role=offer)');
      }
      sessionId = envelope['session'] as String?;

      final pc = await _createPc();

      await pc.setRemoteDescription(
        RTCSessionDescription(envelope['sdp'] as String, 'offer'),
      );
      await _applyRemoteIce(envelope['ice'] as List<dynamic>?);

      final answer = await pc.createAnswer({});
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
    } catch (e) {
      lastError = 'Could not use invite: $e';
      status = lastError;
      notifyListeners();
      rethrow;
    }
  }

  /// Host: apply guest answer from QR / paste.
  Future<void> acceptAnswer(String rawAnswer) async {
    final pc = _pc;
    if (pc == null) {
      throw StateError('Start hosting before accepting an answer');
    }
    try {
      final envelope = SdpQrCodec.decodeEnvelope(rawAnswer);
      if (envelope['role'] != 'answer') {
        throw const FormatException('Expected a guest answer (role=answer)');
      }
      if (sessionId != null &&
          envelope['session'] != null &&
          envelope['session'] != sessionId) {
        throw const FormatException(
          'Answer session does not match this invite. '
          'Use the answer from the guest who scanned this invite.',
        );
      }

      lastError = null;
      await pc.setRemoteDescription(
        RTCSessionDescription(envelope['sdp'] as String, 'answer'),
      );
      await _applyRemoteIce(envelope['ice'] as List<dynamic>?);
      status = 'Connecting…';
      _armConnectTimeout();
      notifyListeners();
    } catch (e) {
      lastError = 'Could not apply answer: $e';
      status = lastError;
      notifyListeners();
      rethrow;
    }
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
    _connectTimer?.cancel();
    _connectTimer = null;
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
    lastError = null;
    mediaReady = false;
    _mediaUpgradeStarted = false;
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
