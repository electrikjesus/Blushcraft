import 'package:flutter/material.dart';

import '../theme.dart';

class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    required this.onPressed,
    this.label = 'Share',
    this.outlined = false,
  });

  final VoidCallback onPressed;
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.ios_share, size: 18),
        label: Text(label),
      );
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.ios_share, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: BlushTheme.roseDeep,
      ),
    );
  }
}
