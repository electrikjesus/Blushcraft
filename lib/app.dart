import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/card_repository.dart';
import 'models/game_state.dart';
import 'networking/game_message.dart';
import 'networking/nearby_game_session.dart';
import 'state/game_controller.dart';
import 'state/stats_store.dart';
import 'ui/game_screen.dart';
import 'ui/home_screen.dart';
import 'ui/how_to_play_screen.dart';
import 'ui/lobby_screen.dart';
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

enum AppScreen { home, lobby, game }

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  CardRepository? _cards;
  StatsStore? _stats;
  GameController? _controller;
  NearbyGameSession? _session;
  AppScreen _screen = AppScreen.home;
  String _displayName = 'Player';
  double _riskayLevel = 0.5;
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
      setState(() {
        _cards = cards;
        _stats = stats;
        if (savedName != null && savedName.isNotEmpty) {
          _displayName = savedName;
        }
        if (savedRiskay != null) {
          _riskayLevel = savedRiskay.clamp(0.0, 1.0);
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
    final stats = _stats!..resetGameResultGate();

    final controller = GameController(
      cards: _cards!,
      stats: stats,
      displayName: name,
      isHost: true,
      riskayLevel: _riskayLevel,
    );

    late final NearbyGameSession session;
    session = NearbyGameSession(
      userName: name,
      onMessage: (msg) async {
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
      },
      onConnection: ({required connected, endpointId, endpointName, isReconnect = false}) async {
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
    final stats = _stats!..resetGameResultGate();

    final controller = GameController(
      cards: _cards!,
      stats: stats,
      displayName: name,
      isHost: false,
      riskayLevel: _riskayLevel,
    );

    late final NearbyGameSession session;
    session = NearbyGameSession(
      userName: name,
      onMessage: (msg) async {
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
        final phase = controller.state?.phase;
        if (phase != null &&
            phase != GamePhase.lobby &&
            phase != GamePhase.disconnected &&
            mounted &&
            _screen == AppScreen.lobby) {
          setState(() => _screen = AppScreen.game);
        }
      },
      onConnection: ({required connected, endpointId, endpointName, isReconnect = false}) async {
        if (!connected) {
          controller.markDisconnected();
          await session.beginReconnectDiscovery();
          if (mounted) setState(() {});
          return;
        }
        await session.send(
          HelloMessage(playerId: controller.localPlayerId, name: name),
        );
        if (isReconnect) {
          // Host will broadcast restored state after Hello.
        }
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

  Future<void> _startDryRun(String name) async {
    await _persistName(name);
    final controller = GameController(
      cards: _cards!,
      stats: _stats!..resetGameResultGate(),
      displayName: name,
      isHost: true,
      dryRun: true,
      riskayLevel: _riskayLevel,
    );
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
          onHost: _startHost,
          onJoin: _startJoin,
          onDryRun: _startDryRun,
          onStats: _openStats,
          onHowTo: _openHowTo,
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
