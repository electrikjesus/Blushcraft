import 'package:flutter/foundation.dart';

import 'game_message.dart';

enum TransportConnectionState {
  idle,
  connecting,
  connected,
  disconnected,
}

typedef MessageHandler = Future<void> Function(GameMessage message);
typedef ConnectionHandler = void Function({
  required bool connected,
  String? endpointId,
  String? endpointName,
  bool isReconnect,
});

/// Shared surface for Nearby, LAN, and WebRTC sessions used by the app shell.
abstract class GameSession extends ChangeNotifier {
  bool get isConnected;
  String? get status;
  Future<void> send(GameMessage message);
  Future<void> stopAll();
}

/// Local Host/Join with discovery (LAN WebSocket or Nearby).
abstract class LocalDiscoverySession extends GameSession {
  Map<String, String> get discovered;

  Future<void> startHosting();
  Future<void> startJoining();
  Future<void> connectTo(String endpointId);
  Future<void> ensureHostingForReconnect();
  Future<void> beginReconnectDiscovery();
}
