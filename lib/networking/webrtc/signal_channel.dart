/// Pluggable signaling for WebRTC.
///
/// v1: [QrSignalChannel] (manual QR / paste).
/// Later: Supabase / Cloudflare implementations with the same surface.
abstract class SignalChannel {
  Future<void> publishOffer(String sessionId, String payload);
  Future<void> publishAnswer(String sessionId, String payload);
  Future<String?> waitForAnswer(String sessionId);
  Future<void> dispose();
}

/// Out-of-band signaling via QR / clipboard (no network middleman).
class QrSignalChannel implements SignalChannel {
  String? localOffer;
  String? localAnswer;
  String? remoteOffer;
  String? remoteAnswer;

  @override
  Future<void> publishOffer(String sessionId, String payload) async {
    localOffer = payload;
  }

  @override
  Future<void> publishAnswer(String sessionId, String payload) async {
    localAnswer = payload;
  }

  @override
  Future<String?> waitForAnswer(String sessionId) async {
    return remoteAnswer;
  }

  @override
  Future<void> dispose() async {
    localOffer = null;
    localAnswer = null;
    remoteOffer = null;
    remoteAnswer = null;
  }
}
