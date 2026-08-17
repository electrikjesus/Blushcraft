import 'package:flutter/material.dart';

import '../../models/game_mode.dart';
import 'adaptive.dart';
import 'theme.dart';
import 'widgets/game_mode_picker.dart';
import 'widgets/riskay_slider.dart';

enum _PlayTransport { local, online }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onHost,
    required this.onJoin,
    required this.onHostOnline,
    required this.onJoinOnline,
    required this.onDryRun,
    required this.onStats,
    required this.onHowTo,
    required this.initialName,
    required this.riskayLevel,
    required this.onRiskayChanged,
    required this.gameMode,
    required this.onGameModeChanged,
  });

  final ValueChanged<String> onHost;
  final ValueChanged<String> onJoin;
  final ValueChanged<String> onHostOnline;
  final ValueChanged<String> onJoinOnline;
  final ValueChanged<String> onDryRun;
  final VoidCallback onStats;
  final VoidCallback onHowTo;
  final String initialName;
  final double riskayLevel;
  final ValueChanged<double> onRiskayChanged;
  final GameMode gameMode;
  final ValueChanged<GameMode> onGameModeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _name;
  late final AnimationController _pulse;
  _PlayTransport _transport = _PlayTransport.local;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _name.dispose();
    _pulse.dispose();
    super.dispose();
  }

  String get _trimmed =>
      _name.text.trim().isEmpty ? 'Player' : _name.text.trim();

  bool get _online => _transport == _PlayTransport.online;

  void _onHost() {
    if (_online) {
      widget.onHostOnline(_trimmed);
    } else {
      widget.onHost(_trimmed);
    }
  }

  void _onJoin() {
    if (_online) {
      widget.onJoinOnline(_trimmed);
    } else {
      widget.onJoin(_trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlushBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final win = BlushWindowSize.fromSize(
                Size(constraints.maxWidth, constraints.maxHeight),
              );
              final brand = _brand(win);
              final form = _form();

              Widget body;
              if (win.preferSplit && constraints.maxWidth >= 560) {
                body = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 4, child: brand),
                    SizedBox(width: win.pagePadding),
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(child: form),
                    ),
                  ],
                );
              } else {
                body = AdaptiveScrollBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      brand,
                      const SizedBox(height: 32),
                      form,
                      const SizedBox(height: 16),
                      Text(
                        'First to 5 points wins the prize.',
                        textAlign: TextAlign.center,
                        style: BlushTheme.body(
                          13,
                          color: BlushTheme.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              }

              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: win.pagePadding,
                  vertical: 20,
                ),
                child: BlushContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: widget.onHowTo,
                              child: const Text('How to play'),
                            ),
                            IconButton(
                              tooltip: 'Stats',
                              onPressed: widget.onStats,
                              icon: const Icon(Icons.favorite_border),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(child: body),
                      if (win.preferSplit && constraints.maxWidth >= 560)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'First to 5 points wins the prize.',
                            textAlign: TextAlign.center,
                            style: BlushTheme.body(
                              13,
                              color: BlushTheme.inkMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _brand(BlushWindowSize win) {
    return FadeTransition(
      opacity: Tween(begin: 0.85, end: 1.0).animate(_pulse),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Blushcraft',
            textAlign: TextAlign.center,
            style: BlushTheme.display(
              win.widthExpanded
                  ? 64
                  : win.heightCompact
                      ? 40
                      : 48,
              weight: FontWeight.w700,
              color: BlushTheme.roseDeep,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            win.preferSplit
                ? 'A two-player card game for romantic & playful moments.'
                : 'A two-player card game for romantic &\nplayful moments.',
            textAlign: TextAlign.center,
            style: BlushTheme.body(
              17,
              color: BlushTheme.inkMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'What should we call you?',
          ),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 20),
        GameModePicker(
          value: widget.gameMode,
          onChanged: widget.onGameModeChanged,
        ),
        const SizedBox(height: 20),
        RiskaySlider(
          value: widget.riskayLevel,
          onChanged: widget.onRiskayChanged,
        ),
        const SizedBox(height: 24),
        Text(
          'Play over',
          style: BlushTheme.body(13, color: BlushTheme.inkMuted),
        ),
        const SizedBox(height: 8),
        SegmentedButton<_PlayTransport>(
          segments: const [
            ButtonSegment(
              value: _PlayTransport.local,
              label: Text('Local'),
              icon: Icon(Icons.wifi, size: 18),
            ),
            ButtonSegment(
              value: _PlayTransport.online,
              label: Text('Online'),
              icon: Icon(Icons.qr_code_2, size: 18),
            ),
          ],
          selected: {_transport},
          onSelectionChanged: (next) {
            if (next.isEmpty) return;
            setState(() => _transport = next.first);
          },
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return BlushTheme.roseDeep;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return BlushTheme.rose;
              }
              return BlushTheme.cardFace;
            }),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _online
              ? 'QR / paste invite over WebRTC (best on Wi‑Fi).'
              : 'Same Wi‑Fi — no Google Play Services needed.',
          style: BlushTheme.body(13, color: BlushTheme.inkMuted),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _onHost,
          style: _online
              ? ElevatedButton.styleFrom(
                  backgroundColor: BlushTheme.roseDeep,
                )
              : null,
          child: Text(_online ? 'Host online' : 'Host local'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _onJoin,
          child: Text(_online ? 'Join online' : 'Join local'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => widget.onDryRun(_trimmed),
          child: Text(
            'Practice on this device',
            style: BlushTheme.body(
              14,
              color: BlushTheme.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}
