import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:blushcraft/data/card_repository.dart';
import 'package:blushcraft/models/card.dart';
import 'package:blushcraft/models/game_mode.dart';

void main() {
  test('StatementCard fills first blank only', () {
    const s = StatementCard(
      id: 15,
      text: 'If you _______________ right now, I\'d _______________.',
    );
    expect(
      s.fillWith('smile'),
      "If you smile right now, I'd ….",
    );
  });

  test('StatementCard with single blank', () {
    const s = StatementCard(
      id: 1,
      text: 'I love it most when you look at me like _______________.',
    );
    expect(
      s.fillWith('A slow dance in the kitchen.'),
      'I love it most when you look at me like A slow dance in the kitchen..',
    );
  });

  test('Riskay pool mixes packs by slider', () {
    final repo = CardRepository.forTesting(
      romanticStatements: [
        const StatementCard(id: 1, text: 'd', heat: CardHeat.defaults),
        const StatementCard(id: 2, text: 'i', heat: CardHeat.innocent),
        const StatementCard(id: 3, text: 'p', heat: CardHeat.provocative),
      ],
      romanticChoices: [
        const ChoiceCard(id: 1, text: 'd', heat: CardHeat.defaults),
        const ChoiceCard(id: 2, text: 'i', heat: CardHeat.innocent),
        const ChoiceCard(id: 3, text: 'p', heat: CardHeat.provocative),
      ],
    );

    final mid = repo.poolForRiskay(0.5, random: Random(1));
    expect(mid.statements.every((s) => s.heat == CardHeat.defaults), isTrue);
    expect(mid.choices.every((c) => c.heat == CardHeat.defaults), isTrue);

    final soft = repo.poolForRiskay(0.0, random: Random(1));
    expect(soft.statements.any((s) => s.heat == CardHeat.innocent), isTrue);
    expect(soft.statements.any((s) => s.heat == CardHeat.provocative), isFalse);

    final hot = repo.poolForRiskay(1.0, random: Random(1));
    expect(hot.statements.any((s) => s.heat == CardHeat.provocative), isTrue);
    expect(hot.statements.any((s) => s.heat == CardHeat.innocent), isFalse);
  });

  test('Mode pools do not cross-contaminate', () {
    final repo = CardRepository.forTesting(
      romanticStatements: [
        const StatementCard(
          id: 1,
          text: 'romantic default',
          heat: CardHeat.defaults,
        ),
      ],
      romanticChoices: [
        const ChoiceCard(id: 1, text: 'romantic choice', heat: CardHeat.defaults),
      ],
      freshStatements: [
        const StatementCard(
          id: 1,
          text: 'fresh default',
          heat: CardHeat.defaults,
        ),
        const StatementCard(
          id: 2,
          text: 'fresh innocent',
          heat: CardHeat.innocent,
        ),
      ],
      freshChoices: [
        const ChoiceCard(id: 1, text: 'fresh choice', heat: CardHeat.defaults),
      ],
    );

    final romantic = repo.poolFor(GameMode.romantic, 0.5, random: Random(1));
    expect(romantic.statements.map((s) => s.text), ['romantic default']);
    expect(romantic.choices.map((c) => c.text), ['romantic choice']);

    final fresh = repo.poolFor(GameMode.freshStart, 0.0, random: Random(1));
    expect(fresh.statements.any((s) => s.text.contains('romantic')), isFalse);
    expect(fresh.statements.any((s) => s.text.contains('fresh')), isTrue);
    expect(
      repo.statementById(1, mode: GameMode.freshStart)?.text,
      'fresh default',
    );
    expect(
      repo.statementById(1, mode: GameMode.romantic)?.text,
      'romantic default',
    );
  });

  test('Riskay labels', () {
    expect(CardRepository.labelForRiskay(0.0), 'Innocent');
    expect(CardRepository.labelForRiskay(0.5), 'Blush');
    expect(CardRepository.labelForRiskay(1.0), 'Riskay');
  });
}
