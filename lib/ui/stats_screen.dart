import 'package:flutter/material.dart';

import '../../share/share_service.dart';
import '../../state/stats_store.dart';
import 'adaptive.dart';
import 'theme.dart';
import 'widgets/share_button.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({
    super.key,
    required this.stats,
    this.onClear,
  });

  final PlayerStats stats;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final pad = BlushWindowSize.of(context).pagePadding;
    return BlushBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Stats'),
          actions: [
            if (onClear != null)
              IconButton(
                tooltip: 'Reset stats',
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        body: BlushContentWidth(
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
            children: [
              Text('Your blush ledger', style: BlushTheme.display(28)),
              const SizedBox(height: 20),
              _statRow('Games played', '${stats.gamesPlayed}'),
              _statRow('Wins', '${stats.wins}'),
              _statRow('Losses', '${stats.losses}'),
              _statRow('Rounds played', '${stats.roundsPlayed}'),
              const SizedBox(height: 24),
              ShareButton(
                onPressed: () => const ShareService().shareStats(stats),
                label: 'Share stats',
              ),
              const SizedBox(height: 32),
              Text('Recent combos', style: BlushTheme.display(22)),
              const SizedBox(height: 12),
              if (stats.recentCombos.isEmpty)
                Text(
                  'No combos yet. Go play a round.',
                  style: BlushTheme.body(15, color: BlushTheme.inkMuted),
                )
              else
                ...stats.recentCombos.map((c) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: BlushTheme.cardFace.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.statementText,
                            style: BlushTheme.body(14, weight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text('• ${c.hostChoiceText}', style: BlushTheme.body(13)),
                          Text('• ${c.guestChoiceText}', style: BlushTheme.body(13)),
                          const SizedBox(height: 6),
                          Text(
                            'Point to ${c.winnerName}',
                            style: BlushTheme.body(
                              12,
                              color: BlushTheme.roseDeep,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  const ShareService().shareCombo(c),
                              child: const Text('Share'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: BlushTheme.body(16))),
          Text(value, style: BlushTheme.display(22, color: BlushTheme.roseDeep)),
        ],
      ),
    );
  }
}
