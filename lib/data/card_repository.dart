import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/card.dart';

/// Active statement/choice pools for a given Riskay setting.
class CardPool {
  const CardPool({
    required this.statements,
    required this.choices,
  });

  final List<StatementCard> statements;
  final List<ChoiceCard> choices;
}

class CardRepository {
  CardRepository._(this.allStatements, this.allChoices);

  /// Test helper: builds a repo without loading assets.
  factory CardRepository.forTesting({
    required List<StatementCard> statements,
    required List<ChoiceCard> choices,
  }) {
    return CardRepository._(statements, choices);
  }

  final List<StatementCard> allStatements;
  final List<ChoiceCard> allChoices;

  static CardRepository? _instance;

  static Future<CardRepository> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/cards.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final statements = (json['statements'] as List<dynamic>)
        .map((e) => StatementCard.fromJson(e as Map<String, dynamic>))
        .toList();
    final choices = (json['choices'] as List<dynamic>)
        .map((e) => ChoiceCard.fromJson(e as Map<String, dynamic>))
        .toList();
    _instance = CardRepository._(statements, choices);
    return _instance!;
  }

  /// Back-compat accessors used by older call sites.
  List<StatementCard> get statements => allStatements;
  List<ChoiceCard> get choices => allChoices;

  StatementCard? statementById(int id) {
    for (final s in allStatements) {
      if (s.id == id) return s;
    }
    return null;
  }

  ChoiceCard? choiceById(int id) {
    for (final c in allChoices) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<StatementCard> _byHeatS(CardHeat heat) =>
      allStatements.where((s) => s.heat == heat).toList();

  List<ChoiceCard> _byHeatC(CardHeat heat) =>
      allChoices.where((c) => c.heat == heat).toList();

  /// Riskay 0.0 = Innocent · 0.5 = Blush (default only) · 1.0 = Riskay.
  /// Default pack is always included; side packs mix in by distance from center.
  CardPool poolForRiskay(double riskay, {Random? random}) {
    final rng = random ?? Random();
    final r = riskay.clamp(0.0, 1.0);

    final statements = <StatementCard>[..._byHeatS(CardHeat.defaults)];
    final choices = <ChoiceCard>[..._byHeatC(CardHeat.defaults)];

    if (r < 0.5) {
      final weight = (0.5 - r) / 0.5; // 0 at center → 1 at innocent
      statements.addAll(_sample(_byHeatS(CardHeat.innocent), weight, rng));
      choices.addAll(_sample(_byHeatC(CardHeat.innocent), weight, rng));
    } else if (r > 0.5) {
      final weight = (r - 0.5) / 0.5; // 0 at center → 1 at riskay
      statements.addAll(_sample(_byHeatS(CardHeat.provocative), weight, rng));
      choices.addAll(_sample(_byHeatC(CardHeat.provocative), weight, rng));
    }

    return CardPool(statements: statements, choices: choices);
  }

  static List<T> _sample<T>(List<T> pack, double weight, Random rng) {
    if (pack.isEmpty || weight <= 0) return const [];
    if (weight >= 0.99) return List<T>.from(pack);
    final shuffled = List<T>.from(pack)..shuffle(rng);
    final count = (pack.length * weight).round().clamp(1, pack.length);
    return shuffled.take(count).toList();
  }

  static String labelForRiskay(double riskay) {
    if (riskay < 0.28) return 'Innocent';
    if (riskay < 0.42) return 'Soft blush';
    if (riskay <= 0.58) return 'Blush';
    if (riskay < 0.78) return 'Spicy';
    return 'Riskay';
  }
}
