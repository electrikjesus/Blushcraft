import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/card.dart';
import '../models/game_mode.dart';

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
  CardRepository._({
    required this.romanticStatements,
    required this.romanticChoices,
    required this.freshStatements,
    required this.freshChoices,
  });

  /// Test helper: builds a repo without loading assets.
  factory CardRepository.forTesting({
    List<StatementCard> romanticStatements = const [],
    List<ChoiceCard> romanticChoices = const [],
    List<StatementCard> freshStatements = const [],
    List<ChoiceCard> freshChoices = const [],
  }) {
    return CardRepository._(
      romanticStatements: romanticStatements,
      romanticChoices: romanticChoices,
      freshStatements: freshStatements,
      freshChoices: freshChoices,
    );
  }

  final List<StatementCard> romanticStatements;
  final List<ChoiceCard> romanticChoices;
  final List<StatementCard> freshStatements;
  final List<ChoiceCard> freshChoices;

  static CardRepository? _instance;

  /// Clears the cached singleton (tests only).
  @visibleForTesting
  static void resetForTesting() => _instance = null;

  static Future<CardRepository> load() async {
    if (_instance != null) return _instance!;
    final romantic = await _loadPack('assets/cards.json');
    final fresh = await _loadPack('assets/cards_fresh_start.json');
    _instance = CardRepository._(
      romanticStatements: romantic.$1,
      romanticChoices: romantic.$2,
      freshStatements: fresh.$1,
      freshChoices: fresh.$2,
    );
    return _instance!;
  }

  static Future<(List<StatementCard>, List<ChoiceCard>)> _loadPack(
    String asset,
  ) async {
    final raw = await rootBundle.loadString(asset);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final statements = (json['statements'] as List<dynamic>)
        .map((e) => StatementCard.fromJson(e as Map<String, dynamic>))
        .toList();
    final choices = (json['choices'] as List<dynamic>)
        .map((e) => ChoiceCard.fromJson(e as Map<String, dynamic>))
        .toList();
    return (statements, choices);
  }

  /// Back-compat: romantic deck statements.
  List<StatementCard> get statements => romanticStatements;

  /// Back-compat: romantic deck choices.
  List<ChoiceCard> get choices => romanticChoices;

  List<StatementCard> statementsFor(GameMode mode) => switch (mode) {
        GameMode.romantic || GameMode.bff => romanticStatements,
        GameMode.freshStart => freshStatements,
      };

  List<ChoiceCard> choicesFor(GameMode mode) => switch (mode) {
        GameMode.romantic || GameMode.bff => romanticChoices,
        GameMode.freshStart => freshChoices,
      };

  StatementCard? statementById(int id, {required GameMode mode}) {
    for (final s in statementsFor(mode)) {
      if (s.id == id) return s;
    }
    return null;
  }

  ChoiceCard? choiceById(int id, {required GameMode mode}) {
    for (final c in choicesFor(mode)) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<StatementCard> _byHeatS(GameMode mode, CardHeat heat) =>
      statementsFor(mode).where((s) => s.heat == heat).toList();

  List<ChoiceCard> _byHeatC(GameMode mode, CardHeat heat) =>
      choicesFor(mode).where((c) => c.heat == heat).toList();

  /// Riskay 0.0 = Innocent · 0.5 = Blush (default only) · 1.0 = Riskay.
  /// Default pack is always included; side packs mix in by distance from center.
  CardPool poolFor(GameMode mode, double riskay, {Random? random}) {
    final playable = mode == GameMode.bff ? GameMode.romantic : mode;
    final rng = random ?? Random();
    final r = riskay.clamp(0.0, 1.0);

    final statements = <StatementCard>[
      ..._byHeatS(playable, CardHeat.defaults),
    ];
    final choices = <ChoiceCard>[..._byHeatC(playable, CardHeat.defaults)];

    if (r < 0.5) {
      final weight = (0.5 - r) / 0.5;
      statements.addAll(
        _sample(_byHeatS(playable, CardHeat.innocent), weight, rng),
      );
      choices.addAll(
        _sample(_byHeatC(playable, CardHeat.innocent), weight, rng),
      );
    } else if (r > 0.5) {
      final weight = (r - 0.5) / 0.5;
      statements.addAll(
        _sample(_byHeatS(playable, CardHeat.provocative), weight, rng),
      );
      choices.addAll(
        _sample(_byHeatC(playable, CardHeat.provocative), weight, rng),
      );
    }

    return CardPool(statements: statements, choices: choices);
  }

  /// Back-compat alias (romantic deck).
  CardPool poolForRiskay(double riskay, {Random? random}) =>
      poolFor(GameMode.romantic, riskay, random: random);

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
