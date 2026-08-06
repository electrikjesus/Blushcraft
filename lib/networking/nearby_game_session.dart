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
    // permission_handler no-ops / auto-grants entries unsupported on the OS.
    await <Permission>[
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
      Permission.accessLocalNetwork, // Android 17+ / targetSdk 37+ Wi‑Fi LAN
    ].request();

    final service = await Permission.locationWhenInUse.serviceStatus;
    if (!service.isEnabled) {
      status =
          'Turn on Location (system setting) to find hosts nearby, then try again.';
      notifyListeners();
      return false;
    }

    final locationOk = await Permission.locationWhenInUse.isGranted;
    if (!locationOk) {
      status = 'Location permission is required for Nearby join/host.';
      notifyListeners();
      return false;
    }

    final bluetoothOk = await Permission.bluetoothScan.isGranted ||
        await Permission.bluetooth.isGranted;
    final connectOk = await Permission.bluetoothConnect.isGranted ||
        await Permission.bluetooth.isGranted;
    if (!bluetoothOk || !connectOk) {
      status =
          'Bluetooth / Nearby devices permission is required. Allow it in Settings.';
      notifyListeners();
      return false;
    }

    // Fail only when the OS actually supports these and the user denied them.
    if (!await _optionalNearbyGranted(Permission.nearbyWifiDevices)) {
      status =
          'Nearby Wi‑Fi devices permission is required to find a host. Allow it in Settings.';
      notifyListeners();
      return false;
    }
    if (!await _optionalNearbyGranted(Permission.accessLocalNetwork)) {
      status =
          'Local network permission is required to join nearby games. Allow it in Settings.';
      notifyListeners();
      return false;
    }

    status = 'Permissions ready';
    notifyListeners();
    return true;
  }

  /// True if granted, or if the permission isn't applicable on this OS build.
  ///
  /// [permission_handler] reports unsupported API-gated permissions as
  /// [PermissionStatus.denied] with no rationale (empty manifest name list).
  /// A real "Don't ask again" denial is [PermissionStatus.permanentlyDenied].
  Future<bool> _optionalNearbyGranted(Permission permission) async {
    final status = await permission.status;
    if (status.isGranted || status.isLimited || status.isRestricted) {
      return true;
    }
    if (status.isPermanentlyDenied) {
      return false;
    }
    if (status.isDenied && await permission.shouldShowRequestRationale) {
      return false;
    }
    // Unsupported on this OS (or never prompted): don't block.
    return true;
  }

  Future<void> startHosting() async {
    await _stopDiscoveryQuiet();
    if (_hadConnection || connectedEndpointId != null) {
      await stopEndpointsOnly();
    }
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
      status = _friendlyNearbyError('Host', e);
      notifyListeners();
    }
  }

  Future<void> startJoining() async {
    await _stopAdvertisingQuiet();
    await _stopDiscoveryQuiet();
    // Avoid stopAllEndpoints on a cold join — it can leave Play Services in a
    // bad state and surface as INTERNAL_ERROR (8) on startDiscovery.
    if (_hadConnection || connectedEndpointId != null) {
      await stopEndpointsOnly();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final allowed = await ensurePermissions();
    if (!allowed) return;
    await _startDiscoveryInternal();
  }

  Future<void> _startDiscoveryInternal({bool isRetry = false}) async {
    try {
      if (discovering) {
        try {
          await _nearby.stopDiscovery();
        } catch (_) {}
        discovering = false;
        await Future<void>.delayed(const Duration(milliseconds: 200));
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
      final raw = '$e';
      if (!isRetry &&
          (raw.contains('INTERNAL_ERROR') ||
              raw.contains('8:') ||
              raw.contains('STATUS_ERROR'))) {
        try {
          await _nearby.stopDiscovery();
        } catch (_) {}
        discovering = false;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return _startDiscoveryInternal(isRetry: true);
      }
      status = _friendlyNearbyError('Join', e);
      notifyListeners();
    }
  }

  String _friendlyNearbyError(String action, Object e) {
    final raw = '$e';
    if (raw.contains('INTERNAL_ERROR') || raw.contains('8:')) {
      return '$action failed (Nearby internal error). '
          'Turn on Bluetooth and Location, wait a second, and try again. '
          'If it keeps failing, update Google Play Services.';
    }
    if (raw.contains('MISSING_PERMISSION') || raw.contains('803')) {
      return '$action failed: a Nearby permission is missing. '
          'Open Settings → Apps → Blushcraft → Permissions and allow '
          'Location and Nearby devices / Bluetooth.';
    }
    if (raw.contains('RADIO_ERROR') || raw.contains('8007')) {
      return '$action failed: Bluetooth/Wi‑Fi radio error. Toggle Bluetooth off/on.';
    }
    return '$action error: $e';
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
      status = _friendlyNearbyError('Connect', e);
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
