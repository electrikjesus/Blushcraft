import 'package:flutter/material.dart';

import '../theme.dart';

class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.text,
    this.isStatement = false,
    this.compact = false,
    this.selected = false,
    this.onTap,
  });

  final String text;
  final bool isStatement;
  final bool compact;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isStatement ? BlushTheme.statementFace : BlushTheme.cardFace;
    final fg = isStatement ? BlushTheme.cream : BlushTheme.charcoal;

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.all(compact ? 14 : 22),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? BlushTheme.rose : Colors.transparent,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: BlushTheme.rose.withValues(alpha: 0.12),
            blurRadius: selected ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isStatement ? 'STATEMENT' : 'CHOICE',
            style: BlushTheme.body(
              11,
              weight: FontWeight.w700,
              color: isStatement
                  ? BlushTheme.blush
                  : BlushTheme.rose.withValues(alpha: 0.8),
            ).copyWith(letterSpacing: 1.4),
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            text,
            style: isStatement
                ? BlushTheme.display(compact ? 18 : 22, color: fg)
                : BlushTheme.body(compact ? 14 : 16, color: fg),
          ),
        ],
      ),
    );

    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}

class CardBack extends StatelessWidget {
  const CardBack({super.key, this.label = 'Blushcraft'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: BlushTheme.rose,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          label,
          style: BlushTheme.display(20, color: Colors.white),
        ),
      ),
    );
  }
}
