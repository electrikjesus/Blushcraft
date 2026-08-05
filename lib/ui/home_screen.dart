import 'package:flutter/material.dart';

import '../../models/game_mode.dart';
import 'theme.dart';
import 'widgets/game_mode_picker.dart';
import 'widgets/riskay_slider.dart';

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

  @override
  Widget build(BuildContext context) {
    return BlushBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 700;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 64 : 24,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 40,
                  ),
                  child: IntrinsicHeight(
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
                        const SizedBox(height: 24),
                        FadeTransition(
                          opacity:
                              Tween(begin: 0.85, end: 1.0).animate(_pulse),
                          child: Column(
                            children: [
                              Text(
                                'Blushcraft',
                                textAlign: TextAlign.center,
                                style: BlushTheme.display(
                                  wide ? 64 : 48,
                                  weight: FontWeight.w700,
                                  color: BlushTheme.roseDeep,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'A two-player card game for romantic &\nplayful moments.',
                                textAlign: TextAlign.center,
                                style: BlushTheme.body(
                                  17,
                                  color: BlushTheme.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
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
                          'Nearby (same room)',
                          style: BlushTheme.body(13, color: BlushTheme.inkMuted),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => widget.onHost(_trimmed),
                          child: const Text('Host nearby'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => widget.onJoin(_trimmed),
                          child: const Text('Join nearby'),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Online (QR / internet)',
                          style: BlushTheme.body(13, color: BlushTheme.inkMuted),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => widget.onHostOnline(_trimmed),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BlushTheme.roseDeep,
                          ),
                          child: const Text('Host online'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => widget.onJoinOnline(_trimmed),
                          child: const Text('Join online'),
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
                        const Spacer(),
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
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
