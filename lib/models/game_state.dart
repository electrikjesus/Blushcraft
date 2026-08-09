import 'game_mode.dart';
import 'player.dart';
import 'round_result.dart';

enum GamePhase {
  lobby,
  selecting,
  waitingForOpponent,
  reveal,
  reaction,
  roundResult,
  gameOver,
  disconnected,
}

class GameState {
  const GameState({
    required this.phase,
    required this.host,
    required this.guest,
    required this.localPlayerId,
    this.statementId,
    this.statementText,
    this.hostHand = const [],
    this.guestHand = const [],
    this.hostSubmittedChoiceId,
    this.guestSubmittedChoiceId,
    this.hostSubmittedChoiceText,
    this.guestSubmittedChoiceText,
    this.lastCombo,
    this.prize,
    this.message,
    this.pointsToWin = 5,
    this.roundNumber = 0,
    this.hostReactionVote,
    this.guestReactionVote,
    this.riskayLevel = 0.5,
    this.gameMode = GameMode.romantic,
    this.isTieBreaker = false,
  });

  final GamePhase phase;
  final PlayerInfo host;
  final PlayerInfo guest;
  final String localPlayerId;
  final int? statementId;
  final String? statementText;
  final List<int> hostHand;
  final List<int> guestHand;
  final int? hostSubmittedChoiceId;
  final int? guestSubmittedChoiceId;
  final String? hostSubmittedChoiceText;
  final String? guestSubmittedChoiceText;
  final RoundCombo? lastCombo;
  final String? prize;
  final String? message;
  final int pointsToWin;
  final int roundNumber;

  /// Player id each side thinks should win the reaction check.
  final String? hostReactionVote;
  final String? guestReactionVote;

  /// 0.0 Innocent · 0.5 Blush (default) · 1.0 Riskay.
  final double riskayLevel;

  /// Deck mode (Romantic / Fresh Start / …). Locked at deal time.
  final GameMode gameMode;

  /// True while resolving a reaction disagreement (same scored roundNumber).
  final bool isTieBreaker;

  bool get isHost => localPlayerId == host.id;
  bool get isGuest => localPlayerId == guest.id;

  PlayerInfo get localPlayer => isHost ? host : guest;
  PlayerInfo get remotePlayer => isHost ? guest : host;

  List<int> get localHand => isHost ? hostHand : guestHand;

  bool get localHasSubmitted =>
      isHost ? hostSubmittedChoiceId != null : guestSubmittedChoiceId != null;

  bool get bothSubmitted =>
      hostSubmittedChoiceId != null && guestSubmittedChoiceId != null;

  bool get bothVoted =>
      hostReactionVote != null && guestReactionVote != null;

  bool get votesAgree =>
      bothVoted && hostReactionVote == guestReactionVote;

  GameState copyWith({
    GamePhase? phase,
    PlayerInfo? host,
    PlayerInfo? guest,
    String? localPlayerId,
    int? statementId,
    String? statementText,
    List<int>? hostHand,
    List<int>? guestHand,
    int? hostSubmittedChoiceId,
    int? guestSubmittedChoiceId,
    String? hostSubmittedChoiceText,
    String? guestSubmittedChoiceText,
    RoundCombo? lastCombo,
    String? prize,
    String? message,
    int? pointsToWin,
    int? roundNumber,
    String? hostReactionVote,
    String? guestReactionVote,
    double? riskayLevel,
    GameMode? gameMode,
    bool? isTieBreaker,
    bool clearStatement = false,
    bool clearSubmissions = false,
    bool clearVotes = false,
    bool clearPrize = false,
    bool clearLastCombo = false,
  }) {
    return GameState(
      phase: phase ?? this.phase,
      host: host ?? this.host,
      guest: guest ?? this.guest,
      localPlayerId: localPlayerId ?? this.localPlayerId,
      statementId: clearStatement ? null : (statementId ?? this.statementId),
      statementText:
          clearStatement ? null : (statementText ?? this.statementText),
      hostHand: hostHand ?? this.hostHand,
      guestHand: guestHand ?? this.guestHand,
      hostSubmittedChoiceId: clearSubmissions
          ? null
          : (hostSubmittedChoiceId ?? this.hostSubmittedChoiceId),
      guestSubmittedChoiceId: clearSubmissions
          ? null
          : (guestSubmittedChoiceId ?? this.guestSubmittedChoiceId),
      hostSubmittedChoiceText: clearSubmissions
          ? null
          : (hostSubmittedChoiceText ?? this.hostSubmittedChoiceText),
      guestSubmittedChoiceText: clearSubmissions
          ? null
          : (guestSubmittedChoiceText ?? this.guestSubmittedChoiceText),
      lastCombo: clearLastCombo ? null : (lastCombo ?? this.lastCombo),
      prize: clearPrize ? null : (prize ?? this.prize),
      message: message ?? this.message,
      pointsToWin: pointsToWin ?? this.pointsToWin,
      roundNumber: roundNumber ?? this.roundNumber,
      hostReactionVote:
          clearVotes ? null : (hostReactionVote ?? this.hostReactionVote),
      guestReactionVote:
          clearVotes ? null : (guestReactionVote ?? this.guestReactionVote),
      riskayLevel: riskayLevel ?? this.riskayLevel,
      gameMode: gameMode ?? this.gameMode,
      isTieBreaker: isTieBreaker ?? this.isTieBreaker,
    );
  }

  /// Snapshot safe to send over the wire (includes localPlayerId for recipient).
  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'host': host.toJson(),
        'guest': guest.toJson(),
        'localPlayerId': localPlayerId,
        'statementId': statementId,
        'statementText': statementText,
        'hostHand': hostHand,
        'guestHand': guestHand,
        'hostSubmittedChoiceId': hostSubmittedChoiceId,
        'guestSubmittedChoiceId': guestSubmittedChoiceId,
        'hostSubmittedChoiceText': hostSubmittedChoiceText,
        'guestSubmittedChoiceText': guestSubmittedChoiceText,
        'lastCombo': lastCombo?.toJson(),
        'prize': prize,
        'message': message,
        'pointsToWin': pointsToWin,
        'roundNumber': roundNumber,
        'hostReactionVote': hostReactionVote,
        'guestReactionVote': guestReactionVote,
        'riskayLevel': riskayLevel,
        'gameMode': gameMode.wireName,
        'isTieBreaker': isTieBreaker,
      };

  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      phase: GamePhase.values.byName(json['phase'] as String),
      host: PlayerInfo.fromJson(json['host'] as Map<String, dynamic>),
      guest: PlayerInfo.fromJson(json['guest'] as Map<String, dynamic>),
      localPlayerId: json['localPlayerId'] as String,
      statementId: json['statementId'] as int?,
      statementText: json['statementText'] as String?,
      hostHand: (json['hostHand'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList(),
      guestHand: (json['guestHand'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList(),
      hostSubmittedChoiceId: json['hostSubmittedChoiceId'] as int?,
      guestSubmittedChoiceId: json['guestSubmittedChoiceId'] as int?,
      hostSubmittedChoiceText: json['hostSubmittedChoiceText'] as String?,
      guestSubmittedChoiceText: json['guestSubmittedChoiceText'] as String?,
      lastCombo: json['lastCombo'] != null
          ? RoundCombo.fromJson(json['lastCombo'] as Map<String, dynamic>)
          : null,
      prize: json['prize'] as String?,
      message: json['message'] as String?,
      pointsToWin: json['pointsToWin'] as int? ?? 5,
      roundNumber: json['roundNumber'] as int? ?? 0,
      hostReactionVote: json['hostReactionVote'] as String?,
      guestReactionVote: json['guestReactionVote'] as String?,
      riskayLevel: (json['riskayLevel'] as num?)?.toDouble() ?? 0.5,
      gameMode: GameMode.fromWire(json['gameMode'] as String?),
      isTieBreaker: json['isTieBreaker'] as bool? ?? false,
    );
  }

  /// Remap snapshot so [viewerId] is treated as the local player.
  GameState forViewer(String viewerId) {
    return copyWith(localPlayerId: viewerId);
  }
}

