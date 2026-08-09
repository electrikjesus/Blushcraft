import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'game_message.dart';
import 'game_transport.dart';

/// Local same-Wi‑Fi session via mDNS discovery + WebSocket (no Play Services).
class LanGameSession extends LocalDiscoverySession {
  LanGameSession({
    required this.userName,
    required this.onMessage,
    this.onConnection,
  });

  static const serviceType = '_blushcraft._tcp';

  final String userName;
  final MessageHandler onMessage;
  final ConnectionHandler? onConnection;

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;
  WebSocket? _socket;
  StreamSubscription? _socketSub;

  String? connectedEndpointId;
  String? connectedEndpointName;
  bool advertising = false;
  bool discovering = false;
  bool reconnecting = false;
  bool _hadConnection = false;
  bool _acceptingGuests = true;

  final Map<String, _LanEndpoint> _endpoints = {};

  @override
  String? status;

  @override
  final Map<String, String> discovered = {};

  @override
  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  Future<bool> ensurePermissions() async {
    await Permission.accessLocalNetwork.request();
    status = 'Permissions ready';
    notifyListeners();
    return true;
  }

  @override
  Future<void> startHosting() async {
    await _stopDiscoveryQuiet();
    await _closeSocketQuiet();
    final allowed = await ensurePermissions();
    if (!allowed) return;
    await _startHostingInternal();
  }

  Future<void> _startHostingInternal() async {
    try {
      await _stopBroadcastQuiet();
      await _stopServerQuiet();

      _acceptingGuests = true;
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = _server!.port;
      _server!.listen(_onHttpRequest, onError: (Object e) {
        debugPrint('LAN server error: $e');
      });

      final service = BonsoirService(
        name: userName,
        type: serviceType,
        port: port,
        attributes: {
          'app': 'blushcraft',
          'player': userName,
        },
      );
      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.initialize();
      await _broadcast!.start();
      advertising = true;
      status = reconnecting
          ? 'Waiting for partner to reconnect…'
          : 'Hosting on Wi‑Fi: waiting for partner…';
      notifyListeners();
    } catch (e) {
      status = 'Host failed: $e';
      advertising = false;
      notifyListeners();
    }
  }

  void _onHttpRequest(HttpRequest request) {
    if (!_acceptingGuests) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write('Blushcraft LAN expects a WebSocket upgrade.');
      request.response.close();
      return;
    }
    WebSocketTransformer.upgrade(request).then((socket) {
      unawaited(_attachSocket(
        socket,
        endpointId: 'guest-${socket.hashCode}',
        endpointName: 'Partner',
        asHost: true,
      ));
    }).catchError((Object e) {
      debugPrint('WebSocket upgrade failed: $e');
    });
  }

  Future<void> _attachSocket(
    WebSocket socket, {
    required String endpointId,
    required String endpointName,
    required bool asHost,
  }) async {
    await _closeSocketQuiet(notifyDisconnect: false);
    _socket = socket;
    connectedEndpointId = endpointId;
    connectedEndpointName = endpointName;
    final wasReconnect = _hadConnection || reconnecting;
    _hadConnection = true;
    reconnecting = false;
    if (asHost) {
      // Prefer a single guest; keep advertising for reconnect.
      _acceptingGuests = false;
    }

    _socketSub = socket.listen(
      (dynamic data) async {
        if (data is! String) return;
        try {
          final message = GameMessage.decode(data);
          if (message is HelloMessage) {
            connectedEndpointName = message.name;
            connectedEndpointId = message.playerId;
          }
          await onMessage(message);
        } catch (e) {
          debugPrint('LAN payload decode error: $e');
        }
      },
      onDone: () => _handleDisconnect(endpointId),
      onError: (Object e) {
        debugPrint('LAN socket error: $e');
        _handleDisconnect(endpointId);
      },
      cancelOnError: true,
    );

    onConnection?.call(
      connected: true,
      endpointId: connectedEndpointId,
      endpointName: connectedEndpointName,
      isReconnect: wasReconnect,
    );
    status = wasReconnect ? 'Partner reconnected' : 'Partner connected';
    notifyListeners();
  }

  void _handleDisconnect(String id) {
    if (connectedEndpointId != null &&
        connectedEndpointId != id &&
        id != 'guest-${_socket.hashCode}') {
      // Ignore stale disconnect if we already re-bound.
    }
    final previous = connectedEndpointId ?? id;
    connectedEndpointId = null;
    connectedEndpointName = null;
    _socket = null;
    _socketSub = null;
    reconnecting = true;
    _acceptingGuests = true;
    onConnection?.call(
      connected: false,
      endpointId: previous,
      isReconnect: false,
    );
    status = 'Partner disconnected; reconnecting…';
    notifyListeners();
  }

  @override
  Future<void> startJoining() async {
    await _stopBroadcastQuiet();
    await _stopServerQuiet();
    await _closeSocketQuiet();
    final allowed = await ensurePermissions();
    if (!allowed) return;
    await _startDiscoveryInternal();
  }

  Future<void> _startDiscoveryInternal() async {
    try {
      await _stopDiscoveryQuiet();
      discovered.clear();
      _endpoints.clear();

      final discovery = BonsoirDiscovery(type: serviceType);
      await discovery.initialize();
      _discoverySub = discovery.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            event.service.resolve(discovery.serviceResolver);
          case BonsoirDiscoveryServiceResolvedEvent():
            _onResolved(event.service);
          case BonsoirDiscoveryServiceUpdatedEvent():
            _onResolved(event.service);
          case BonsoirDiscoveryServiceLostEvent():
            _onLost(event.service);
          default:
            break;
        }
      });
      await discovery.start();
      _discovery = discovery;
      discovering = true;
      status = reconnecting
          ? 'Searching to reconnect…'
          : 'Searching for a host on Wi‑Fi…';
      notifyListeners();
    } catch (e) {
      discovering = false;
      status =
          'Join failed: $e. Stay on the same Wi‑Fi and allow local network access.';
      notifyListeners();
    }
  }

  void _onResolved(BonsoirService service) {
    final host = service.hostAddress;
    if (host == null || host.isEmpty) return;
    final id = '$host:${service.port}';
    final name = service.attributes['player'] ?? service.name;
    _endpoints[id] = _LanEndpoint(host: host, port: service.port, name: name);
    discovered[id] = name;
    status = reconnecting ? 'Found host: tap Connect' : 'Found: $name';
    notifyListeners();
  }

  void _onLost(BonsoirService service) {
    final toRemove = <String>[];
    for (final e in _endpoints.entries) {
      if (e.value.name == service.name ||
          e.value.name == service.attributes['player']) {
        toRemove.add(e.key);
      }
    }
    for (final id in toRemove) {
      _endpoints.remove(id);
      discovered.remove(id);
    }
    notifyListeners();
  }

  @override
  Future<void> connectTo(String endpointId) async {
    final ep = _endpoints[endpointId];
    if (ep == null) {
      status = 'Host is no longer available; search again.';
      notifyListeners();
      return;
    }
    try {
      status = 'Connecting to ${ep.name}…';
      notifyListeners();
      final uri = Uri(scheme: 'ws', host: ep.host, port: ep.port, path: '/');
      final socket = await WebSocket.connect(uri.toString());
      await _stopDiscoveryQuiet();
      await _attachSocket(
        socket,
        endpointId: endpointId,
        endpointName: ep.name,
        asHost: false,
      );
    } catch (e) {
      status = 'Connect failed: $e';
      notifyListeners();
    }
  }

  @override
  Future<void> ensureHostingForReconnect() async {
    reconnecting = true;
    _acceptingGuests = true;
    status = 'Waiting for partner to reconnect…';
    notifyListeners();
    if (!advertising || _server == null) {
      await _startHostingInternal();
    } else {
      notifyListeners();
    }
  }

  @override
  Future<void> beginReconnectDiscovery() async {
    reconnecting = true;
    connectedEndpointId = null;
    status = 'Searching to reconnect…';
    notifyListeners();
    await _startDiscoveryInternal();
  }

  @override
  Future<void> send(GameMessage message) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(message.encode());
  }

  Future<void> _closeSocketQuiet({bool notifyDisconnect = true}) async {
    try {
      await _socketSub?.cancel();
    } catch (_) {}
    _socketSub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    if (notifyDisconnect && _socket != null) {
      // already closed
    }
    _socket = null;
  }

  Future<void> _stopServerQuiet() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }

  Future<void> _stopBroadcastQuiet() async {
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;
    advertising = false;
  }

  Future<void> _stopDiscoveryQuiet() async {
    try {
      await _discoverySub?.cancel();
    } catch (_) {}
    _discoverySub = null;
    try {
      await _discovery?.stop();
    } catch (_) {}
    _discovery = null;
    discovering = false;
  }

  @override
  Future<void> stopAll() async {
    reconnecting = false;
    _hadConnection = false;
    _acceptingGuests = true;
    await _closeSocketQuiet(notifyDisconnect: false);
    await _stopBroadcastQuiet();
    await _stopDiscoveryQuiet();
    await _stopServerQuiet();
    connectedEndpointId = null;
    connectedEndpointName = null;
    discovered.clear();
    _endpoints.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stopAll());
    super.dispose();
  }
}

class _LanEndpoint {
  const _LanEndpoint({
    required this.host,
    required this.port,
    required this.name,
  });

  final String host;
  final int port;
  final String name;
}
