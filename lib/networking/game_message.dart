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
      case WebrtcVideoSignalMessage.typeName:
        return WebrtcVideoSignalMessage.fromJson(map);
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
      case ChatInviteMessage.typeName:
        return ChatInviteMessage.fromJson(map);
      case ChatInviteReplyMessage.typeName:
        return ChatInviteReplyMessage.fromJson(map);
      case ChatEndMessage.typeName:
        return ChatEndMessage.fromJson(map);
      case ChatTextMessage.typeName:
        return ChatTextMessage.fromJson(map);
      case ChatPhotoMessage.typeName:
        return ChatPhotoMessage.fromJson(map);
      case ChatAudioMessage.typeName:
        return ChatAudioMessage.fromJson(map);
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

/// Encoded audio chunk for reaction-phase voice (throttled/buffered by sender).
class PeerAudioMessage extends GameMessage {
  const PeerAudioMessage({
    required this.playerId,
    required this.base64Aac,
    this.mime = 'audio/aac',
  });

  static const typeName = 'peer_audio';

  final String playerId;
  final String base64Aac;

  /// Wire mime for playback (`audio/aac`, `audio/ogg`, …).
  final String mime;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'base64Aac': base64Aac,
        'mime': mime,
      };

  factory PeerAudioMessage.fromJson(Map<String, dynamic> json) {
    return PeerAudioMessage(
      playerId: json['playerId'] as String,
      base64Aac: json['base64Aac'] as String,
      mime: json['mime'] as String? ?? 'audio/aac',
    );
  }
}

/// Privacy flags so the peer can hide PiP / mute playback.
class AvPrivacyMessage extends GameMessage {
  const AvPrivacyMessage({
    required this.playerId,
    required this.cameraEnabled,
    required this.micEnabled,
    this.liveViewEnabled = false,
    this.hasCamera = true,
    this.audioLevel = 0,
  });

  static const typeName = 'av_privacy';

  final String playerId;
  final bool cameraEnabled;
  final bool micEnabled;

  /// When true, this player wants the mutual live media strip/panel.
  final bool liveViewEnabled;

  /// Device has a usable camera (false → prefer audio-only live media).
  final bool hasCamera;

  /// Local mic level 0–1 (for partner diagnostics UI).
  final double audioLevel;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'cameraEnabled': cameraEnabled,
        'micEnabled': micEnabled,
        'liveViewEnabled': liveViewEnabled,
        'hasCamera': hasCamera,
        'audioLevel': audioLevel,
      };

  factory AvPrivacyMessage.fromJson(Map<String, dynamic> json) {
    final levelRaw = json['audioLevel'];
    final level = levelRaw is num ? levelRaw.toDouble() : 0.0;
    return AvPrivacyMessage(
      playerId: json['playerId'] as String,
      cameraEnabled: json['cameraEnabled'] as bool? ?? false,
      micEnabled: json['micEnabled'] as bool? ?? false,
      liveViewEnabled: json['liveViewEnabled'] as bool? ?? false,
      // Older clients omit this — assume they may have a camera.
      hasCamera: json['hasCamera'] as bool? ?? true,
      audioLevel: level.clamp(0.0, 1.0),
    );
  }
}

/// LAN WebRTC video signaling (offer / answer / ICE / bye) over the game socket.
///
/// Audio stays on [PeerAudioMessage]; this is video-only.
class WebrtcVideoSignalMessage extends GameMessage {
  const WebrtcVideoSignalMessage({
    required this.op,
    this.sdp,
    this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  static const typeName = 'webrtc_video';

  /// `offer` | `answer` | `ice` | `bye`
  final String op;
  final String? sdp;
  final String? candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'op': op,
        if (sdp != null) 'sdp': sdp,
        if (candidate != null) 'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
      };

  factory WebrtcVideoSignalMessage.fromJson(Map<String, dynamic> json) {
    return WebrtcVideoSignalMessage(
      op: json['op'] as String,
      sdp: json['sdp'] as String?,
      candidate: json['candidate'] as String?,
      sdpMid: json['sdpMid'] as String?,
      sdpMLineIndex: json['sdpMLineIndex'] as int?,
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

/// Request mutual consent to open peer chat.
class ChatInviteMessage extends GameMessage {
  const ChatInviteMessage({required this.fromPlayerId});

  static const typeName = 'chat_invite';

  final String fromPlayerId;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'fromPlayerId': fromPlayerId};

  factory ChatInviteMessage.fromJson(Map<String, dynamic> json) {
    return ChatInviteMessage(fromPlayerId: json['fromPlayerId'] as String);
  }
}

class ChatInviteReplyMessage extends GameMessage {
  const ChatInviteReplyMessage({
    required this.fromPlayerId,
    required this.accepted,
  });

  static const typeName = 'chat_invite_reply';

  final String fromPlayerId;
  final bool accepted;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'fromPlayerId': fromPlayerId,
        'accepted': accepted,
      };

  factory ChatInviteReplyMessage.fromJson(Map<String, dynamic> json) {
    return ChatInviteReplyMessage(
      fromPlayerId: json['fromPlayerId'] as String,
      accepted: json['accepted'] as bool? ?? false,
    );
  }
}

class ChatEndMessage extends GameMessage {
  const ChatEndMessage({required this.fromPlayerId});

  static const typeName = 'chat_end';

  final String fromPlayerId;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'fromPlayerId': fromPlayerId};

  factory ChatEndMessage.fromJson(Map<String, dynamic> json) {
    return ChatEndMessage(fromPlayerId: json['fromPlayerId'] as String);
  }
}

class ChatTextMessage extends GameMessage {
  const ChatTextMessage({
    required this.fromPlayerId,
    required this.id,
    required this.text,
    required this.sentAtMs,
  });

  static const typeName = 'chat_text';

  final String fromPlayerId;
  final String id;
  final String text;
  final int sentAtMs;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'fromPlayerId': fromPlayerId,
        'id': id,
        'text': text,
        'sentAtMs': sentAtMs,
      };

  factory ChatTextMessage.fromJson(Map<String, dynamic> json) {
    return ChatTextMessage(
      fromPlayerId: json['fromPlayerId'] as String,
      id: json['id'] as String,
      text: json['text'] as String,
      sentAtMs: json['sentAtMs'] as int? ?? 0,
    );
  }
}

class ChatPhotoMessage extends GameMessage {
  const ChatPhotoMessage({
    required this.fromPlayerId,
    required this.id,
    required this.mime,
    required this.base64Jpeg,
    required this.sentAtMs,
  });

  static const typeName = 'chat_photo';

  final String fromPlayerId;
  final String id;
  final String mime;
  final String base64Jpeg;
  final int sentAtMs;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'fromPlayerId': fromPlayerId,
        'id': id,
        'mime': mime,
        'base64Jpeg': base64Jpeg,
        'sentAtMs': sentAtMs,
      };

  factory ChatPhotoMessage.fromJson(Map<String, dynamic> json) {
    return ChatPhotoMessage(
      fromPlayerId: json['fromPlayerId'] as String,
      id: json['id'] as String,
      mime: json['mime'] as String? ?? 'image/jpeg',
      base64Jpeg: json['base64Jpeg'] as String,
      sentAtMs: json['sentAtMs'] as int? ?? 0,
    );
  }
}

/// Session chat voice note (compressed AAC/Opus, base64).
class ChatAudioMessage extends GameMessage {
  const ChatAudioMessage({
    required this.fromPlayerId,
    required this.id,
    required this.mime,
    required this.base64Audio,
    required this.sentAtMs,
    this.durationMs = 0,
  });

  static const typeName = 'chat_audio';

  final String fromPlayerId;
  final String id;
  final String mime;
  final String base64Audio;
  final int sentAtMs;
  final int durationMs;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {
        'fromPlayerId': fromPlayerId,
        'id': id,
        'mime': mime,
        'base64Audio': base64Audio,
        'sentAtMs': sentAtMs,
        'durationMs': durationMs,
      };

  factory ChatAudioMessage.fromJson(Map<String, dynamic> json) {
    return ChatAudioMessage(
      fromPlayerId: json['fromPlayerId'] as String,
      id: json['id'] as String,
      mime: json['mime'] as String? ?? 'audio/aac',
      base64Audio: json['base64Audio'] as String,
      sentAtMs: json['sentAtMs'] as int? ?? 0,
      durationMs: json['durationMs'] as int? ?? 0,
    );
  }
}
