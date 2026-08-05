import 'package:flutter/material.dart';

import '../../models/game_mode.dart';
import '../theme.dart';

/// Compact mode picker. BFF is visible but disabled (coming soon).
class GameModePicker extends StatelessWidget {
  const GameModePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final GameMode value;
  final ValueChanged<GameMode> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Game mode', style: BlushTheme.display(18)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in GameMode.values)
              _ModeChip(
                mode: mode,
                selected: value == mode,
                enabled: enabled && mode.isSelectable,
                onTap: () {
                  if (!enabled || !mode.isSelectable) return;
                  onChanged(mode);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value.blurb,
          style: BlushTheme.body(13, color: BlushTheme.inkMuted),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final GameMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = mode == GameMode.bff ? '${mode.label} (soon)' : mode.label;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled ? (_) => onTap() : null,
      selectedColor: BlushTheme.blush,
      checkmarkColor: BlushTheme.roseDeep,
      labelStyle: BlushTheme.body(
        13,
        weight: FontWeight.w600,
        color: enabled ? BlushTheme.charcoal : BlushTheme.inkMuted,
      ),
      side: BorderSide(
        color: selected ? BlushTheme.rose : BlushTheme.creamDark,
        width: selected ? 1.5 : 1,
      ),
      backgroundColor: BlushTheme.cardFace,
      showCheckmark: selected,
    );
  }
}
