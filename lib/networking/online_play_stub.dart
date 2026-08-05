/// Future hook for internet play (Supabase rooms + WebRTC selfie).
/// Not used in v1; local Nearby Connections only.
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
      'Online play is not available yet. Use Host / Join for local play.',
    );
  }

  @override
  Future<void> joinRoom({
    required String roomCode,
    required String displayName,
  }) async {
    throw UnimplementedError(
      'Online play is not available yet. Use Host / Join for local play.',
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
