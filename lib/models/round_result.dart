import 'card.dart';

class RoundCombo {
  const RoundCombo({
    required this.statementText,
    required this.statementId,
    required this.hostChoiceText,
    required this.hostChoiceId,
    required this.guestChoiceText,
    required this.guestChoiceId,
    required this.winnerId,
    required this.winnerName,
  });

  final String statementText;
  final int statementId;
  final String hostChoiceText;
  final int hostChoiceId;
  final String guestChoiceText;
  final int guestChoiceId;
  final String winnerId;
  final String winnerName;

  String get hostFilled =>
      statementText.contains('_')
          ? _fill(statementText, hostChoiceText)
          : '$statementText $hostChoiceText';

  String get guestFilled =>
      statementText.contains('_')
          ? _fill(statementText, guestChoiceText)
          : '$statementText $guestChoiceText';

  static String _fill(String statement, String choice) {
    final blank = RegExp(r'_+');
    var first = true;
    return statement.replaceAllMapped(blank, (m) {
      if (first) {
        first = false;
        return StatementCard.normalizeChoiceForBlank(
          choice,
          sentenceInitial:
              StatementCard.isSentenceInitialBlank(statement, m.start),
        );
      }
      return '…';
    });
  }

  String toShareText() {
    return 'Blushcraft combo\n'
        'Prompt: $statementText\n'
        '• $hostChoiceText\n'
        '• $guestChoiceText\n'
        'Round to: $winnerName';
  }

  factory RoundCombo.fromJson(Map<String, dynamic> json) {
    return RoundCombo(
      statementText: json['statementText'] as String,
      statementId: json['statementId'] as int,
      hostChoiceText: json['hostChoiceText'] as String,
      hostChoiceId: json['hostChoiceId'] as int,
      guestChoiceText: json['guestChoiceText'] as String,
      guestChoiceId: json['guestChoiceId'] as int,
      winnerId: json['winnerId'] as String,
      winnerName: json['winnerName'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'statementText': statementText,
        'statementId': statementId,
        'hostChoiceText': hostChoiceText,
        'hostChoiceId': hostChoiceId,
        'guestChoiceText': guestChoiceText,
        'guestChoiceId': guestChoiceId,
        'winnerId': winnerId,
        'winnerName': winnerName,
      };
}
