enum CardHeat {
  innocent,
  defaults, // "default" is a reserved word in some contexts; use defaults
  provocative;

  static CardHeat fromJson(String? raw) {
    switch (raw) {
      case 'innocent':
        return CardHeat.innocent;
      case 'provocative':
        return CardHeat.provocative;
      case 'default':
      default:
        return CardHeat.defaults;
    }
  }

  String toJson() {
    switch (this) {
      case CardHeat.innocent:
        return 'innocent';
      case CardHeat.provocative:
        return 'provocative';
      case CardHeat.defaults:
        return 'default';
    }
  }
}

class StatementCard {
  const StatementCard({
    required this.id,
    required this.text,
    this.heat = CardHeat.defaults,
  });

  final int id;
  final String text;
  final CardHeat heat;

  factory StatementCard.fromJson(Map<String, dynamic> json) {
    return StatementCard(
      id: json['id'] as int,
      text: json['text'] as String,
      heat: CardHeat.fromJson(json['heat'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'heat': heat.toJson(),
      };

  /// Normalize choice text for insertion into a blank.
  ///
  /// Trims, strips a trailing period, and lowercases the first letter when the
  /// blank is not sentence-initial.
  static String normalizeChoiceForBlank(
    String choiceText, {
    required bool sentenceInitial,
  }) {
    var t = choiceText.trim();
    if (t.endsWith('.')) {
      t = t.substring(0, t.length - 1).trimRight();
    }
    if (!sentenceInitial && t.isNotEmpty) {
      t = '${t[0].toLowerCase()}${t.substring(1)}';
    }
    return t;
  }

  /// Whether [blankStart] in [statement] begins a sentence.
  static bool isSentenceInitialBlank(String statement, int blankStart) {
    final before = statement.substring(0, blankStart);
    final trimmed = before.trimRight();
    return trimmed.isEmpty || trimmed.endsWith('.');
  }

  /// Fill blanks (`_______________`) with [choiceText]. Extra blanks become "…".
  String fillWith(String choiceText) {
    final blank = RegExp(r'_+');
    var remaining = true;
    return text.replaceAllMapped(blank, (match) {
      if (remaining) {
        remaining = false;
        return normalizeChoiceForBlank(
          choiceText,
          sentenceInitial: isSentenceInitialBlank(text, match.start),
        );
      }
      return '…';
    });
  }
}

class ChoiceCard {
  const ChoiceCard({
    required this.id,
    required this.text,
    this.heat = CardHeat.defaults,
  });

  final int id;
  final String text;
  final CardHeat heat;

  factory ChoiceCard.fromJson(Map<String, dynamic> json) {
    return ChoiceCard(
      id: json['id'] as int,
      text: json['text'] as String,
      heat: CardHeat.fromJson(json['heat'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'heat': heat.toJson(),
      };
}
