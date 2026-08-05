import 'package:flutter/material.dart';

import '../../data/card_repository.dart';
import '../theme.dart';

/// Innocent ← Blush → Riskay content heat control.
class RiskaySlider extends StatelessWidget {
  const RiskaySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.compact = false,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = CardRepository.labelForRiskay(value);

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Riskay',
                style: BlushTheme.display(compact ? 18 : 20),
              ),
              const Spacer(),
              Text(
                label,
                style: BlushTheme.body(
                  14,
                  weight: FontWeight.w700,
                  color: BlushTheme.roseDeep,
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Text(
              'Mix the classic blush deck with sweeter or spicier cards.',
              style: BlushTheme.body(13, color: BlushTheme.inkMuted),
            ),
          ],
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: BlushTheme.rose,
              inactiveTrackColor: BlushTheme.creamDark,
              thumbColor: BlushTheme.roseDeep,
              overlayColor: BlushTheme.blush.withValues(alpha: 0.25),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: enabled ? onChanged : null,
              divisions: 10,
            ),
          ),
          Row(
            children: [
              Text(
                'Innocent',
                style: BlushTheme.body(12, color: BlushTheme.inkMuted),
              ),
              const Spacer(),
              Text(
                'Blush',
                style: BlushTheme.body(12, color: BlushTheme.inkMuted),
              ),
              const Spacer(),
              Text(
                'Riskay',
                style: BlushTheme.body(12, color: BlushTheme.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
