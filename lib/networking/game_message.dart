import 'dart:convert';

/// Compact JSON protocol for Nearby payload messages.
sealed class GameMessage {
  const GameMessage();

  String get type;

  Map<String, dynamic> toJson();

  String encode() => jsonEncode({'type': type, ...toJson()});

  static GameMessage decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final type = map['type'] as String;
    switch (type) {
      case HelloMessage.typeName:
        return HelloMessage.fromJson(map);
      case StateSyncMessage.typeName:
        return StateSyncMessage.fromJson(map);
      case SubmitChoiceMessage.typeName:
        return SubmitChoiceMessage.fromJson(map);
      case ReactionVoteMessage.typeName:
        return ReactionVoteMessage.fromJson(map);
      case SetNameMessage.typeName:
        return SetNameMessage.fromJson(map);
      case PeerFrameMessage.typeName:
        return PeerFrameMessage.fromJson(map);
      case PeerAudioMessage.typeName:
        return PeerAudioMessage.fromJson(map);
      case AvPrivacyMessage.typeName:
        return AvPrivacyMessage.fromJson(map);
      case StartGameMessage.typeName:
        return const StartGameMessage();
      case NextRoundMessage.typeName:
        return const NextRoundMessage();
      case SetPrizeMessage.typeName:
        return SetPrizeMessage.fromJson(map);
      case SetRiskayMessage.typeName:
        return SetRiskayMessage.fromJson(map);
      case SetGameModeMessage.typeName:
        return SetGameModeMessage.fromJson(map);
      default:
        throw FormatException('Unknown GameMessage type: $type');
    }
  }
}

class HelloMessage extends GameMessage {
  const HelloMessage({required this.playerId, required this.name});

  static const typeName = 'hello';

  final String playerId;
  final String name;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'playerId': playerId, 'name': name};

  factory HelloMessage.fromJson(Map<String, dynamic> json) {
    return HelloMessage(
      playerId: json['playerId'] as String,
      name: json['name'] as String,
    );
  }
}

class SetNameMessage extends GameMessage {
  const SetNameMessage({required this.playerId, required this.name});

  static const typeName = 'set_name';

  final String playerId;
  final String name;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'playerId': playerId, 'name': name};

  factory SetNameMessage.fromJson(Map<String, dynamic> json) {
    return SetNameMessage(
      playerId: json['playerId'] as String,
      name: json['name'] as String,
    );
  }
}

class StateSyncMessage extends GameMessage {
  const StateSyncMessage({required this.state});

  static const typeName = 'state';

  final Map<String, dynamic> state;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'state': state};

  factory StateSyncMessage.fromJson(Map<String, dynamic> json) {
    return StateSyncMessage(state: json['state'] as Map<String, dynamic>);
  }
}

class SubmitChoiceMessage extends GameMessage {
  const SubmitChoiceMessage({
    required this.playerId,
    required this.choiceId,
  });

  static const typeName = 'submit';

  final String playerId;
  final int choiceId;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'choiceId': choiceId,
      };

  factory SubmitChoiceMessage.fromJson(Map<String, dynamic> json) {
    return SubmitChoiceMessage(
      playerId: json['playerId'] as String,
      choiceId: json['choiceId'] as int,
    );
  }
}

class ReactionVoteMessage extends GameMessage {
  const ReactionVoteMessage({
    required this.voterId,
    required this.winnerId,
  });

  static const typeName = 'reaction';

  final String voterId;

  /// Who should get the point (the one who did NOT blush first).
  final String winnerId;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'voterId': voterId,
        'winnerId': winnerId,
      };

  factory ReactionVoteMessage.fromJson(Map<String, dynamic> json) {
    return ReactionVoteMessage(
      voterId: json['voterId'] as String,
      winnerId: json['winnerId'] as String,
    );
  }
}

class StartGameMessage extends GameMessage {
  const StartGameMessage();

  static const typeName = 'start';

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {};
}

class NextRoundMessage extends GameMessage {
  const NextRoundMessage();

  static const typeName = 'next_round';

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {};
}

class SetPrizeMessage extends GameMessage {
  const SetPrizeMessage({required this.prize});

  static const typeName = 'prize';

  final String prize;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'prize': prize};

  factory SetPrizeMessage.fromJson(Map<String, dynamic> json) {
    return SetPrizeMessage(prize: json['prize'] as String);
  }
}

/// Base64 JPEG frame for reaction PiP (throttled by sender).
class PeerFrameMessage extends GameMessage {
  const PeerFrameMessage({
    required this.playerId,
    required this.base64Jpeg,
  });

  static const typeName = 'peer_frame';

  final String playerId;
  final String base64Jpeg;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'base64Jpeg': base64Jpeg,
      };

  factory PeerFrameMessage.fromJson(Map<String, dynamic> json) {
    return PeerFrameMessage(
      playerId: json['playerId'] as String,
      base64Jpeg: json['base64Jpeg'] as String,
    );
  }
}

/// AAC audio chunk for reaction-phase voice (throttled by sender).
class PeerAudioMessage extends GameMessage {
  const PeerAudioMessage({
    required this.playerId,
    required this.base64Aac,
  });

  static const typeName = 'peer_audio';

  final String playerId;
  final String base64Aac;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'base64Aac': base64Aac,
      };

  factory PeerAudioMessage.fromJson(Map<String, dynamic> json) {
    return PeerAudioMessage(
      playerId: json['playerId'] as String,
      base64Aac: json['base64Aac'] as String,
    );
  }
}

/// Privacy flags so the peer can hide PiP / mute playback.
class AvPrivacyMessage extends GameMessage {
  const AvPrivacyMessage({
    required this.playerId,
    required this.cameraEnabled,
    required this.micEnabled,
  });

  static const typeName = 'av_privacy';

  final String playerId;
  final bool cameraEnabled;
  final bool micEnabled;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'cameraEnabled': cameraEnabled,
        'micEnabled': micEnabled,
      };

  factory AvPrivacyMessage.fromJson(Map<String, dynamic> json) {
    return AvPrivacyMessage(
      playerId: json['playerId'] as String,
      cameraEnabled: json['cameraEnabled'] as bool? ?? false,
      micEnabled: json['micEnabled'] as bool? ?? false,
    );
  }
}

class SetRiskayMessage extends GameMessage {
  const SetRiskayMessage({required this.riskayLevel});

  static const typeName = 'riskay';

  final double riskayLevel;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'riskayLevel': riskayLevel};

  factory SetRiskayMessage.fromJson(Map<String, dynamic> json) {
    return SetRiskayMessage(
      riskayLevel: (json['riskayLevel'] as num).toDouble(),
    );
  }
}

class SetGameModeMessage extends GameMessage {
  const SetGameModeMessage({required this.gameMode});

  static const typeName = 'game_mode';

  final String gameMode;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'gameMode': gameMode};

  factory SetGameModeMessage.fromJson(Map<String, dynamic> json) {
    return SetGameModeMessage(gameMode: json['gameMode'] as String);
  }
}
