import 'package:flutter/material.dart';

import 'theme.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlushBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('How to play')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          children: [
            Text('Blushcraft', style: BlushTheme.display(28)),
            const SizedBox(height: 8),
            Text(
              'A two-player, blush-inducing card game.',
              style: BlushTheme.body(16, color: BlushTheme.inkMuted),
            ),
            const SizedBox(height: 28),
            _section(
              '1. Setup',
              'Host starts a local game on the same Wi‑Fi; your partner taps Join and Connect. '
              'Or use Online with a QR / paste invite. '
              'Each of you gets 7 Choice cards. One Statement card is flipped each round.',
            ),
            _section(
              '2. Submissions',
              'Both players pick one Choice card that makes the most blush-worthy '
              'combo with the prompt. Cards stay face-down until both are in.',
            ),
            _section(
              '3. Reveal & reading',
              'Flip and take turns reading the full statement aloud with your card.',
            ),
            _section(
              '4. Reaction check',
              'Whoever blushes, laughs/smiles first, or breaks eye contact loses the round: '
              'the other player gets the point. If you disagree, read again while holding eye contact. '
              'Reaction camera and mic stay off until you allow them. You can set them up in the '
              'lobby or tap the icons in-game, agree to the short consent prompt, then turn either '
              'off anytime. Your partner only sees or hears you after you opt in.',
            ),
            _section(
              'Connection drops',
              'If the local Wi‑Fi link drops mid-game, stay on the pause screen. The host keeps advertising; '
              'the partner searches and taps Connect again to resume the same round.',
            ),
            _section(
              '5. Scoring',
              'Winner of the round keeps the Statement as 1 point. First to 5 points wins '
              'and chooses a prize (foot massage, breakfast in bed, next date night…).',
            ),
            _section(
              'Game modes',
              'Romantic Partner is the classic couple deck. Fresh Start is for two people who '
              'just met, with prompts meant to learn and startle. BFF mode is coming later. '
              'The host picks the mode before the match starts.',
            ),
            _section(
              'Riskay slider',
              'Set heat before you play: Innocent mixes in sweeter cards, '
              'Blush (center) is the classic deck, and Riskay adds spicier prompts. '
              'The default blush cards are always in the mix. The host locks this in for the game.',
            ),
            _section(
              'Tips',
              'Turn on Location and Bluetooth for Host/Join. '
              'Use Practice mode to try the flow on one phone. '
              'One Choice fills the blank(s) in the Statement.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: BlushTheme.display(20)),
          const SizedBox(height: 8),
          Text(body, style: BlushTheme.body(15)),
        ],
      ),
    );
  }
}
