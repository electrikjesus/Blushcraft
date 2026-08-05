import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import 'game_message.dart';
import 'game_transport.dart';

/// Nearby Connections P2P session for local two-player sync.
class NearbyGameSession extends GameSession {
  NearbyGameSession({
    required this.userName,
    required this.onMessage,
    this.onConnection,
  });

  static const serviceId = 'com.blushcraft.blushcraft';
  static const strategy = Strategy.P2P_STAR;

  final String userName;
  final MessageHandler onMessage;
  final ConnectionHandler? onConnection;

  final _nearby = Nearby();
  String? connectedEndpointId;
  String? connectedEndpointName;
  bool advertising = false;
  bool discovering = false;
  bool reconnecting = false;
  bool _hadConnection = false;

  @override
  String? status;
  final Map<String, String> discovered = {};

  @override
  bool get isConnected => connectedEndpointId != null;

  Future<bool> ensurePermissions() async {
    final perms = <Permission>[
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ];
    final statuses = await perms.request();
    final ok = statuses.values.every(
      (s) => s.isGranted || s.isLimited || s.isRestricted,
    );
    final locationOk = await Permission.locationWhenInUse.isGranted;
    status = locationOk
        ? (ok ? 'Permissions ready' : 'Some permissions missing; try again')
        : 'Location permission required for Nearby';
    notifyListeners();
    return locationOk;
  }

  Future<void> startHosting() async {
    await stopEndpointsOnly();
    await _stopDiscoveryQuiet();
    final allowed = await ensurePermissions();
    if (!allowed) return;
    await _startAdvertisingInternal();
  }

  Future<void> _startAdvertisingInternal() async {
    try {
      if (advertising) {
        try {
          await _nearby.stopAdvertising();
        } catch (_) {}
        advertising = false;
      }
      advertising = await _nearby.startAdvertising(
        userName,
        strategy,
        serviceId: serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: (id, status) {
          this.status = 'Host result: $status';
          if (status == Status.CONNECTED) {
            final wasReconnect = _hadConnection || reconnecting;
            connectedEndpointId = id;
            _hadConnection = true;
            reconnecting = false;
            onConnection?.call(
              connected: true,
              endpointId: id,
              endpointName: connectedEndpointName,
              isReconnect: wasReconnect,
            );
            this.status = wasReconnect
                ? 'Partner reconnected'
                : 'Partner connected';
          }
          notifyListeners();
        },
        onDisconnected: (id) {
          _handleDisconnect(id);
        },
      );
      status = advertising
          ? (reconnecting
              ? 'Waiting for partner to reconnect…'
              : 'Hosting: waiting for partner…')
          : 'Failed to host';
      notifyListeners();
    } catch (e) {
      status = 'Host error: $e';
      notifyListeners();
    }
  }

  Future<void> startJoining() async {
    await stopEndpointsOnly();
    await _stopAdvertisingQuiet();
    final allowed = await ensurePermissions();
    if (!allowed) return;
    await _startDiscoveryInternal();
  }

  Future<void> _startDiscoveryInternal() async {
    try {
      if (discovering) {
        try {
          await _nearby.stopDiscovery();
        } catch (_) {}
        discovering = false;
      }
      discovered.clear();
      discovering = await _nearby.startDiscovery(
        userName,
        strategy,
        serviceId: serviceId,
        onEndpointFound: (id, name, serviceId) {
          discovered[id] = name;
          status = reconnecting ? 'Found host: tap Connect' : 'Found: $name';
          notifyListeners();
        },
        onEndpointLost: (id) {
          if (id != null) discovered.remove(id);
          notifyListeners();
        },
      );
      status = discovering
          ? (reconnecting ? 'Searching to reconnect…' : 'Searching for a host…')
          : 'Failed to search';
      notifyListeners();
    } catch (e) {
      status = 'Join error: $e';
      notifyListeners();
    }
  }

  /// After a drop: host keeps/restarts advertising without wiping session intent.
  Future<void> ensureHostingForReconnect() async {
    reconnecting = true;
    status = 'Waiting for partner to reconnect…';
    notifyListeners();
    if (!advertising) {
      await _startAdvertisingInternal();
    }
  }

  /// After a drop: guest rediscovers hosts to rejoin the in-progress game.
  Future<void> beginReconnectDiscovery() async {
    reconnecting = true;
    connectedEndpointId = null;
    status = 'Searching to reconnect…';
    notifyListeners();
    await _startDiscoveryInternal();
  }

  Future<void> connectTo(String endpointId) async {
    try {
      await _nearby.requestConnection(
        userName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: (id, status) {
          this.status = 'Join result: $status';
          if (status == Status.CONNECTED) {
            final wasReconnect = _hadConnection || reconnecting;
            connectedEndpointId = id;
            connectedEndpointName = discovered[id] ?? connectedEndpointName;
            _hadConnection = true;
            reconnecting = false;
            onConnection?.call(
              connected: true,
              endpointId: id,
              endpointName: connectedEndpointName,
              isReconnect: wasReconnect,
            );
            _nearby.stopDiscovery();
            discovering = false;
            this.status =
                wasReconnect ? 'Reconnected' : 'Connected to host';
          }
          notifyListeners();
        },
        onDisconnected: (id) {
          _handleDisconnect(id);
        },
      );
    } catch (e) {
      status = 'Connect error: $e';
      notifyListeners();
    }
  }

  void _handleDisconnect(String id) {
    if (connectedEndpointId != null && connectedEndpointId != id) return;
    connectedEndpointId = null;
    reconnecting = true;
    onConnection?.call(
      connected: false,
      endpointId: id,
      isReconnect: false,
    );
    status = 'Partner disconnected; reconnecting…';
    notifyListeners();
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    connectedEndpointName = info.endpointName;
    _nearby.acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) async {
        if (payload.type != PayloadType.BYTES || payload.bytes == null) return;
        try {
          final raw = utf8.decode(payload.bytes!);
          final message = GameMessage.decode(raw);
          await onMessage(message);
        } catch (e) {
          debugPrint('Payload decode error: $e');
        }
      },
      onPayloadTransferUpdate: (endpointId, update) {},
    );
  }

  @override
  Future<void> send(GameMessage message) async {
    final id = connectedEndpointId;
    if (id == null) return;
    final bytes = Uint8List.fromList(utf8.encode(message.encode()));
    await _nearby.sendBytesPayload(id, bytes);
  }

  Future<void> stopEndpointsOnly() async {
    try {
      await _nearby.stopAllEndpoints();
    } catch (_) {}
    connectedEndpointId = null;
    connectedEndpointName = null;
  }

  Future<void> _stopAdvertisingQuiet() async {
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    advertising = false;
  }

  Future<void> _stopDiscoveryQuiet() async {
    try {
      await _nearby.stopDiscovery();
    } catch (_) {}
    discovering = false;
  }

  @override
  Future<void> stopAll() async {
    reconnecting = false;
    _hadConnection = false;
    await _stopAdvertisingQuiet();
    await _stopDiscoveryQuiet();
    await stopEndpointsOnly();
    discovered.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stopAll();
    super.dispose();
  }
}
