import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:blushcraft/data/card_repository.dart';
import 'package:blushcraft/models/card.dart';

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
      statements: [
        const StatementCard(id: 1, text: 'd', heat: CardHeat.defaults),
        const StatementCard(id: 2, text: 'i', heat: CardHeat.innocent),
        const StatementCard(id: 3, text: 'p', heat: CardHeat.provocative),
      ],
      choices: [
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

  test('Riskay labels', () {
    expect(CardRepository.labelForRiskay(0.0), 'Innocent');
    expect(CardRepository.labelForRiskay(0.5), 'Blush');
    expect(CardRepository.labelForRiskay(1.0), 'Riskay');
  });
}
