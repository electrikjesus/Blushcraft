/// Online invite / session hooks.
///
/// v1 internet design: WebRTC + QR signaling (see docs/architecture-webrtc-qr.md).
/// Round data stays on-device via GameMessage over an RTCDataChannel.
/// Later: Supabase/Cloudflare replace QR for signaling only - not game state.
abstract class OnlinePlaySession {
  Future<void> createRoom({required String displayName});
  Future<void> joinRoom({required String roomCode, required String displayName});
  Future<void> disconnect();
  Stream<Map<String, dynamic>> get stateStream;
  Future<void> send(Map<String, dynamic> message);
}

class OnlinePlayStub implements OnlinePlaySession {
  @override
  Future<void> createRoom({required String displayName}) async {
    throw UnimplementedError(
      'Online WebRTC+QR play is not implemented yet. '
      'Use Host / Join for local Nearby play. '
      'See docs/architecture-webrtc-qr.md.',
    );
  }

  @override
  Future<void> joinRoom({
    required String roomCode,
    required String displayName,
  }) async {
    throw UnimplementedError(
      'Online WebRTC+QR play is not implemented yet. '
      'Use Host / Join for local Nearby play.',
    );
  }

  @override
  Future<void> disconnect() async {}

  @override
  Stream<Map<String, dynamic>> get stateStream =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Future<void> send(Map<String, dynamic> message) async {
    throw UnimplementedError('Online play is not available yet.');
  }
}
