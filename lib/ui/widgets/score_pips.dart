import 'package:flutter/material.dart';

import '../theme.dart';

class ScorePips extends StatelessWidget {
  const ScorePips({
    super.key,
    required this.hostName,
    required this.guestName,
    required this.hostScore,
    required this.guestScore,
    this.pointsToWin = 5,
  });

  final String hostName;
  final String guestName;
  final int hostScore;
  final int guestScore;
  final int pointsToWin;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _side(hostName, hostScore)),
        Text('vs', style: BlushTheme.body(14, color: BlushTheme.inkMuted)),
        Expanded(child: _side(guestName, guestScore, alignEnd: true)),
      ],
    );
  }

  Widget _side(String name, int score, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: BlushTheme.body(13, weight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment:
              alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: List.generate(pointsToWin, (i) {
            final filled = i < score;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? BlushTheme.rose : Colors.transparent,
                border: Border.all(color: BlushTheme.rose, width: 1.5),
              ),
            );
          }),
        ),
      ],
    );
  }
}
