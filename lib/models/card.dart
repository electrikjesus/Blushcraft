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

  /// Fill blanks (`_______________`) with [choiceText]. Extra blanks become "…".
  String fillWith(String choiceText) {
    final blank = RegExp(r'_+');
    var remaining = true;
    return text.replaceAllMapped(blank, (match) {
      if (remaining) {
        remaining = false;
        return choiceText;
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
