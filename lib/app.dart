import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/card_repository.dart';
import 'models/game_mode.dart';
import 'models/game_state.dart';
import 'networking/game_message.dart';
import 'networking/game_transport.dart';
import 'networking/lan_game_session.dart';
import 'networking/webrtc/webrtc_qr_session.dart';
import 'state/game_controller.dart';
import 'state/stats_store.dart';
import 'ui/game_screen.dart';
import 'ui/home_screen.dart';
import 'ui/how_to_play_screen.dart';
import 'ui/lobby_screen.dart';
import 'ui/online_host_qr_screen.dart';
import 'ui/online_join_qr_screen.dart';
import 'ui/stats_screen.dart';
import 'ui/theme.dart';

class BlushcraftApp extends StatelessWidget {
  const BlushcraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blushcraft',
      debugShowCheckedModeBanner: false,
      theme: BlushTheme.light(),
      home: const AppRoot(),
    );
  }
}

enum AppScreen { home, onlineHost, onlineJoin, lobby, game }

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  CardRepository? _cards;
  StatsStore? _stats;
  GameController? _controller;
  GameSession? _session;
  AppScreen _screen = AppScreen.home;
  String _displayName = 'Player';
  double _riskayLevel = 0.5;
  GameMode _gameMode = GameMode.romantic;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final cards = await CardRepository.load();
      final prefs = await SharedPreferences.getInstance();
      final stats = StatsStore(prefs);
      final savedName = prefs.getString('blushcraft_name');
      final savedRiskay = prefs.getDouble('blushcraft_riskay');
      final savedMode = prefs.getString('blushcraft_game_mode');
      setState(() {
        _cards = cards;
        _stats = stats;
        if (savedName != null && savedName.isNotEmpty) {
          _displayName = savedName;
        }
        if (savedRiskay != null) {
          _riskayLevel = savedRiskay.clamp(0.0, 1.0);
        }
        if (savedMode != null) {
          final mode = GameMode.fromWire(savedMode);
          _gameMode = mode.isSelectable ? mode : GameMode.romantic;
        }
      });
    } catch (e) {
      setState(() => _loadError = '$e');
    }
  }

  Future<void> _persistName(String name) async {
    _displayName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('blushcraft_name', name);
  }

  Future<void> _persistRiskay(double level) async {
    _riskayLevel = level.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('blushcraft_riskay', _riskayLevel);
    setState(() {});
  }

  Future<void> _persistGameMode(GameMode mode) async {
    if (!mode.isSelectable) return;
    _gameMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('blushcraft_game_mode', mode.wireName);
    setState(() {});
  }

  GameController _newController({
    required String name,
    required bool isHost,
    bool dryRun = false,
  }) {
    return GameController(
      cards: _cards!,
      stats: (_stats!..resetGameResultGate()),
      displayName: name,
      isHost: isHost,
      dryRun: dryRun,
      riskayLevel: _riskayLevel,
      gameMode: _gameMode,
    );
  }

  Future<void> _handleGameMessage(
    GameController controller,
    GameMessage msg, {
    bool promoteGuestToGame = false,
  }) async {
    if (msg is PeerFrameMessage) {
      controller.onPeerFrame?.call(msg.playerId, msg.base64Jpeg);
      return;
    }
    if (msg is PeerAudioMessage) {
      controller.onPeerAudio?.call(msg.playerId, msg.base64Aac);
      return;
    }
    if (msg is AvPrivacyMessage) {
      controller.onAvPrivacy?.call(
        msg.playerId,
        cameraEnabled: msg.cameraEnabled,
        micEnabled: msg.micEnabled,
      );
      return;
    }
    await controller.onMessage(msg);
    if (!promoteGuestToGame) return;
    final phase = controller.state?.phase;
    if (phase != null &&
        phase != GamePhase.lobby &&
        phase != GamePhase.disconnected &&
        mounted &&
        _screen == AppScreen.lobby) {
      setState(() => _screen = AppScreen.game);
    }
  }

  Future<void> _leaveToHome() async {
    await _session?.stopAll();
    _session?.dispose();
    _controller?.dispose();
    setState(() {
      _session = null;
      _controller = null;
      _screen = AppScreen.home;
    });
  }

  Future<void> _startHost(String name) async {
    await _persistName(name);
    final controller = _newController(name: name, isHost: true);

    late final LanGameSession session;
    session = LanGameSession(
      userName: name,
      onMessage: (msg) => _handleGameMessage(controller, msg),
      onConnection: ({
        required connected,
        endpointId,
        endpointName,
        isReconnect = false,
      }) async {
        if (!connected) {
          controller.markDisconnected();
          await session.ensureHostingForReconnect();
          if (mounted) setState(() {});
          return;
        }
        if (isReconnect) {
          await controller.resumeAfterReconnect();
        }
        if (mounted) setState(() {});
      },
    );

    controller.sendMessage = session.send;
    await controller.initLobby();
    await session.startHosting();

    setState(() {
      _controller = controller;
      _session = session;
      _screen = AppScreen.lobby;
    });
  }

  Future<void> _startJoin(String name) async {
    await _persistName(name);
    final controller = _newController(name: name, isHost: false);

    late final LanGameSession session;
    session = LanGameSession(
      userName: name,
      onMessage: (msg) => _handleGameMessage(
        controller,
        msg,
        promoteGuestToGame: true,
      ),
      onConnection: ({
        required connected,
        endpointId,
        endpointName,
        isReconnect = false,
      }) async {
        if (!connected) {
          controller.markDisconnected();
          await session.beginReconnectDiscovery();
          if (mounted) setState(() {});
          return;
        }
        await session.send(
          HelloMessage(playerId: controller.localPlayerId, name: name),
        );
        if (mounted) setState(() {});
      },
    );

    controller.sendMessage = session.send;
    await controller.initLobby();
    await session.startJoining();

    setState(() {
      _controller = controller;
      _session = session;
      _screen = AppScreen.lobby;
    });
  }

  Future<void> _startHostOnline(String name) async {
    await _persistName(name);
    final controller = _newController(name: name, isHost: true);

    final session = WebRtcQrSession(
      userName: name,
      onMessage: (msg) => _handleGameMessage(controller, msg),
      onConnection: ({
        required connected,
        endpointId,
        endpointName,
        isReconnect = false,
      }) {
        if (!connected) {
          controller.markDisconnected();
          if (mounted) setState(() {});
          return;
        }
        if (isReconnect) {
          controller.resumeAfterReconnect();
        }
        if (mounted && _screen == AppScreen.onlineHost) {
          setState(() => _screen = AppScreen.lobby);
        } else if (mounted) {
          setState(() {});
        }
      },
    );

    controller.sendMessage = session.send;
    await controller.initLobby();

    setState(() {
      _controller = controller;
      _session = session;
      _screen = AppScreen.onlineHost;
    });
  }

  Future<void> _startJoinOnline(String name) async {
    await _persistName(name);
    final controller = _newController(name: name, isHost: false);

    late final WebRtcQrSession session;
    session = WebRtcQrSession(
      userName: name,
      onMessage: (msg) => _handleGameMessage(
        controller,
        msg,
        promoteGuestToGame: true,
      ),
      onConnection: ({
        required connected,
        endpointId,
        endpointName,
        isReconnect = false,
      }) async {
        if (!connected) {
          controller.markDisconnected();
          if (mounted) setState(() {});
          return;
        }
        await session.send(
          HelloMessage(playerId: controller.localPlayerId, name: name),
        );
        if (mounted && _screen == AppScreen.onlineJoin) {
          setState(() => _screen = AppScreen.lobby);
        } else if (mounted) {
          setState(() {});
        }
      },
    );

    controller.sendMessage = session.send;
    await controller.initLobby();

    setState(() {
      _controller = controller;
      _session = session;
      _screen = AppScreen.onlineJoin;
    });
  }

  Future<void> _startDryRun(String name) async {
    await _persistName(name);
    final controller = _newController(name: name, isHost: true, dryRun: true);
    await controller.initLobby(guestName: 'Partner');
    setState(() {
      _controller = controller;
      _session = null;
      _screen = AppScreen.lobby;
    });
  }

  Future<void> _startGame() async {
    final c = _controller;
    if (c == null) return;
    await c.startGame();
    setState(() => _screen = AppScreen.game);
  }

  void _openStats() {
    final nav = Navigator.of(context);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => StatsScreen(
          stats: _stats!.load(),
          onClear: () async {
            await _stats!.clear();
            if (!mounted) return;
            nav.pop();
            _openStats();
          },
        ),
      ),
    );
  }

  void _openHowTo() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const HowToPlayScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _session?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        body: Center(child: Text('Failed to load cards:\n$_loadError')),
      );
    }
    if (_cards == null || _stats == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    switch (_screen) {
      case AppScreen.home:
        return HomeScreen(
          initialName: _displayName,
          riskayLevel: _riskayLevel,
          onRiskayChanged: _persistRiskay,
          gameMode: _gameMode,
          onGameModeChanged: _persistGameMode,
          onHost: _startHost,
          onJoin: _startJoin,
          onHostOnline: _startHostOnline,
          onJoinOnline: _startJoinOnline,
          onDryRun: _startDryRun,
          onStats: _openStats,
          onHowTo: _openHowTo,
        );
      case AppScreen.onlineHost:
        return OnlineHostQrScreen(
          session: _session as WebRtcQrSession,
          onCancel: _leaveToHome,
          onConnected: () {
            if (mounted && _screen == AppScreen.onlineHost) {
              setState(() => _screen = AppScreen.lobby);
            }
          },
        );
      case AppScreen.onlineJoin:
        return OnlineJoinQrScreen(
          session: _session as WebRtcQrSession,
          onCancel: _leaveToHome,
          onConnected: () {
            if (mounted && _screen == AppScreen.onlineJoin) {
              setState(() => _screen = AppScreen.lobby);
            }
          },
        );
      case AppScreen.lobby:
        return LobbyScreen(
          controller: _controller!,
          session: _session,
          onLeave: _leaveToHome,
          onStart: _startGame,
        );
      case AppScreen.game:
        return GameScreen(
          controller: _controller!,
          session: _session,
          onLeave: _leaveToHome,
        );
    }
  }
}
