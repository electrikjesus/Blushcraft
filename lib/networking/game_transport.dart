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

/// Shared surface for Nearby and WebRTC sessions used by the app shell.
abstract class GameSession extends ChangeNotifier {
  bool get isConnected;
  String? get status;
  Future<void> send(GameMessage message);
  Future<void> stopAll();
}
