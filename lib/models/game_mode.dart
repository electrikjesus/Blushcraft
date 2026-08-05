/// Deck / tone axis separate from Riskay heat.
enum GameMode {
  romantic,
  freshStart,
  bff;

  String get wireName => switch (this) {
        GameMode.romantic => 'romantic',
        GameMode.freshStart => 'freshStart',
        GameMode.bff => 'bff',
      };

  String get label => switch (this) {
        GameMode.romantic => 'Romantic Partner',
        GameMode.freshStart => 'Fresh Start',
        GameMode.bff => 'BFF',
      };

  String get blurb => switch (this) {
        GameMode.romantic =>
          'For couples and close partners. Classic blush energy.',
        GameMode.freshStart =>
          'For two people who just met. Learn something, startle each other.',
        GameMode.bff => 'Coming soon: make each other crack up.',
      };

  bool get isSelectable => this != GameMode.bff;

  static GameMode fromWire(String? raw) {
    switch (raw) {
      case 'freshStart':
        return GameMode.freshStart;
      case 'bff':
        return GameMode.bff;
      case 'romantic':
      default:
        return GameMode.romantic;
    }
  }
}
