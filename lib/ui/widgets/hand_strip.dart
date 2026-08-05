import 'package:flutter/material.dart';

import '../../models/card.dart';
import 'card_face.dart';

class HandStrip extends StatelessWidget {
  const HandStrip({
    super.key,
    required this.choiceIds,
    required this.resolve,
    this.selectedId,
    this.enabled = true,
    this.onSelect,
  });

  final List<int> choiceIds;
  final ChoiceCard? Function(int id) resolve;
  final int? selectedId;
  final bool enabled;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: choiceIds.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final id = choiceIds[i];
          final card = resolve(id);
          if (card == null) return const SizedBox.shrink();
          return SizedBox(
            width: 160,
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: CardFace(
                text: card.text,
                compact: true,
                selected: selectedId == id,
                onTap: enabled && onSelect != null ? () => onSelect!(id) : null,
              ),
            ),
          );
        },
      ),
    );
  }
}
