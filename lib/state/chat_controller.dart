import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../networking/game_message.dart';
import '../util/blush_log.dart';
import '../util/chat_sound_player.dart';

enum ChatConsentStatus {
  /// No mutual consent; cannot send.
  off,

  /// Local player sent an invite; waiting for reply.
  inviteSent,

  /// Peer invited us; waiting for local Allow / Not now.
  inviteIncoming,

  /// Both allowed chat.
  open,
}

enum ChatBubbleKind { text, photo, audio }

class ChatBubble {
  const ChatBubble({
    required this.id,
    required this.fromPlayerId,
    required this.kind,
    required this.sentAtMs,
    this.text,
    this.base64Jpeg,
    this.base64Audio,
    this.mime,
    this.durationMs,
  });

  final String id;
  final String fromPlayerId;
  final ChatBubbleKind kind;
  final int sentAtMs;
  final String? text;
  final String? base64Jpeg;
  final String? base64Audio;
  final String? mime;
  final int? durationMs;

  bool isMine(String localPlayerId) => fromPlayerId == localPlayerId;
}

typedef ChatSend = Future<void> Function(GameMessage message);

/// Peer chat outside host-authoritative game state (session-scoped).
class ChatController extends ChangeNotifier {
  ChatController({
    required this.localPlayerId,
    this.sendMessage,
  });

  final String localPlayerId;
  ChatSend? sendMessage;

  static const maxBase64Chars = 90 * 1024;

  ChatConsentStatus status = ChatConsentStatus.off;
  String? statusHint;
  final List<ChatBubble> messages = [];
  int unreadCount = 0;
  bool panelOpen = false;

  /// Bumps when an invite arrives — UI can animate the banner.
  int invitePulse = 0;

  /// Bumps when a remote message arrives — UI can animate badge / toast.
  int messagePulse = 0;

  /// Latest remote toast line (cleared by UI after showing).
  String? toastHint;

  final _uuid = const Uuid();
  final _sounds = ChatSoundPlayer();

  bool get canSend => status == ChatConsentStatus.open;
  bool get showInviteBanner => status == ChatConsentStatus.inviteIncoming;

  void bindSend(ChatSend? send) {
    sendMessage = send;
  }

  void setPanelOpen(bool open) {
    panelOpen = open;
    if (open) {
      unreadCount = 0;
      toastHint = null;
    }
    notifyListeners();
  }

  void clearToast() {
    if (toastHint == null) return;
    toastHint = null;
    notifyListeners();
  }

  void clearSession() {
    status = ChatConsentStatus.off;
    statusHint = null;
    messages.clear();
    unreadCount = 0;
    panelOpen = false;
    toastHint = null;
    notifyListeners();
  }

  Future<void> invitePartner() async {
    if (status == ChatConsentStatus.open ||
        status == ChatConsentStatus.inviteSent) {
      return;
    }
    if (status == ChatConsentStatus.inviteIncoming) {
      return;
    }
    status = ChatConsentStatus.inviteSent;
    statusHint = 'Invite sent — waiting for your partner…';
    notifyListeners();
    blushLog('Chat', 'invite sent');
    await sendMessage?.call(ChatInviteMessage(fromPlayerId: localPlayerId));
  }

  Future<void> replyToInvite({required bool accepted}) async {
    if (status != ChatConsentStatus.inviteIncoming) return;
    await sendMessage?.call(
      ChatInviteReplyMessage(fromPlayerId: localPlayerId, accepted: accepted),
    );
    if (accepted) {
      status = ChatConsentStatus.open;
      statusHint = 'Chat is on — say something sweet.';
      blushLog('Chat', 'invite accepted (local)');
    } else {
      status = ChatConsentStatus.off;
      statusHint = null;
      blushLog('Chat', 'invite declined (local)');
    }
    notifyListeners();
  }

  Future<void> endChat() async {
    if (status == ChatConsentStatus.off) return;
    status = ChatConsentStatus.off;
    statusHint = 'Chat ended. Invite again anytime.';
    notifyListeners();
    blushLog('Chat', 'end chat');
    await sendMessage?.call(ChatEndMessage(fromPlayerId: localPlayerId));
  }

  Future<String?> sendText(String raw) async {
    if (!canSend) return 'Chat is not open yet.';
    final text = raw.trim();
    if (text.isEmpty) return 'Message is empty.';
    if (text.length > 2000) return 'Message is too long.';
    final id = _uuid.v4();
    final sentAt = DateTime.now().millisecondsSinceEpoch;
    final bubble = ChatBubble(
      id: id,
      fromPlayerId: localPlayerId,
      kind: ChatBubbleKind.text,
      sentAtMs: sentAt,
      text: text,
    );
    messages.add(bubble);
    notifyListeners();
    await sendMessage?.call(
      ChatTextMessage(
        fromPlayerId: localPlayerId,
        id: id,
        text: text,
        sentAtMs: sentAt,
      ),
    );
    return null;
  }

  Future<String?> sendPhotoBase64({
    required String base64Jpeg,
    String mime = 'image/jpeg',
  }) async {
    if (!canSend) return 'Chat is not open yet.';
    if (base64Jpeg.isEmpty) return 'Photo is empty.';
    if (base64Jpeg.length > maxBase64Chars) {
      return 'Photo is too large after compress — try again or pick a smaller image.';
    }
    final id = _uuid.v4();
    final sentAt = DateTime.now().millisecondsSinceEpoch;
    messages.add(
      ChatBubble(
        id: id,
        fromPlayerId: localPlayerId,
        kind: ChatBubbleKind.photo,
        sentAtMs: sentAt,
        base64Jpeg: base64Jpeg,
        mime: mime,
      ),
    );
    notifyListeners();
    await sendMessage?.call(
      ChatPhotoMessage(
        fromPlayerId: localPlayerId,
        id: id,
        mime: mime,
        base64Jpeg: base64Jpeg,
        sentAtMs: sentAt,
      ),
    );
    return null;
  }

  Future<String?> sendAudioBase64({
    required String base64Audio,
    required String mime,
    required int durationMs,
  }) async {
    if (!canSend) return 'Chat is not open yet.';
    if (base64Audio.isEmpty) return 'Voice note is empty.';
    if (base64Audio.length > maxBase64Chars) {
      return 'Voice note is too large — try a shorter take.';
    }
    if (durationMs > 30000) return 'Keep voice notes under 30 seconds.';
    final id = _uuid.v4();
    final sentAt = DateTime.now().millisecondsSinceEpoch;
    messages.add(
      ChatBubble(
        id: id,
        fromPlayerId: localPlayerId,
        kind: ChatBubbleKind.audio,
        sentAtMs: sentAt,
        base64Audio: base64Audio,
        mime: mime,
        durationMs: durationMs,
      ),
    );
    notifyListeners();
    await sendMessage?.call(
      ChatAudioMessage(
        fromPlayerId: localPlayerId,
        id: id,
        mime: mime,
        base64Audio: base64Audio,
        sentAtMs: sentAt,
        durationMs: durationMs,
      ),
    );
    return null;
  }

  void onRemoteMessage(GameMessage msg) {
    switch (msg) {
      case ChatInviteMessage m:
        _onInvite(m);
      case ChatInviteReplyMessage m:
        _onInviteReply(m);
      case ChatEndMessage m:
        _onEnd(m);
      case ChatTextMessage m:
        _onText(m);
      case ChatPhotoMessage m:
        _onPhoto(m);
      case ChatAudioMessage m:
        _onAudio(m);
      default:
        break;
    }
  }

  void _onInvite(ChatInviteMessage m) {
    if (m.fromPlayerId == localPlayerId) return;
    if (status == ChatConsentStatus.open) return;
    status = ChatConsentStatus.inviteIncoming;
    statusHint = 'Your partner wants to chat.';
    invitePulse++;
    toastHint = 'Chat invite';
    unawaited(_sounds.playInvite());
    blushLog('Chat', 'invite incoming');
    notifyListeners();
  }

  void _onInviteReply(ChatInviteReplyMessage m) {
    if (m.fromPlayerId == localPlayerId) return;
    if (m.accepted) {
      status = ChatConsentStatus.open;
      statusHint = 'Chat is on — say something sweet.';
      messagePulse++;
      toastHint = 'Chat allowed';
      unawaited(_sounds.playMessage());
      blushLog('Chat', 'invite accepted (remote)');
    } else if (status == ChatConsentStatus.inviteSent) {
      status = ChatConsentStatus.off;
      statusHint = 'Partner declined chat.';
      blushLog('Chat', 'invite declined (remote)');
    }
    notifyListeners();
  }

  void _onEnd(ChatEndMessage m) {
    if (m.fromPlayerId == localPlayerId) return;
    status = ChatConsentStatus.off;
    statusHint = 'Partner ended chat.';
    blushLog('Chat', 'ended by peer');
    notifyListeners();
  }

  void _onText(ChatTextMessage m) {
    if (m.fromPlayerId == localPlayerId) return;
    if (messages.any((b) => b.id == m.id)) return;
    messages.add(
      ChatBubble(
        id: m.id,
        fromPlayerId: m.fromPlayerId,
        kind: ChatBubbleKind.text,
        sentAtMs: m.sentAtMs,
        text: m.text,
      ),
    );
    _pulseIncoming(
      preview: (m.text.length > 48) ? '${m.text.substring(0, 48)}…' : m.text,
    );
  }

  void _onPhoto(ChatPhotoMessage m) {
    if (m.fromPlayerId == localPlayerId) return;
    if (messages.any((b) => b.id == m.id)) return;
    if (m.base64Jpeg.length > maxBase64Chars) {
      blushLog('Chat', 'drop oversized photo ${m.base64Jpeg.length}');
      return;
    }
    messages.add(
      ChatBubble(
        id: m.id,
        fromPlayerId: m.fromPlayerId,
        kind: ChatBubbleKind.photo,
        sentAtMs: m.sentAtMs,
        base64Jpeg: m.base64Jpeg,
        mime: m.mime,
      ),
    );
    _pulseIncoming(preview: 'Photo');
  }

  void _onAudio(ChatAudioMessage m) {
    if (m.fromPlayerId == localPlayerId) return;
    if (messages.any((b) => b.id == m.id)) return;
    if (m.base64Audio.length > maxBase64Chars) {
      blushLog('Chat', 'drop oversized audio ${m.base64Audio.length}');
      return;
    }
    messages.add(
      ChatBubble(
        id: m.id,
        fromPlayerId: m.fromPlayerId,
        kind: ChatBubbleKind.audio,
        sentAtMs: m.sentAtMs,
        base64Audio: m.base64Audio,
        mime: m.mime,
        durationMs: m.durationMs,
      ),
    );
    final secs = (m.durationMs / 1000).ceil().clamp(1, 99);
    _pulseIncoming(preview: 'Voice note (${secs}s)');
  }

  void _pulseIncoming({required String preview}) {
    if (!panelOpen) unreadCount++;
    messagePulse++;
    toastHint = preview;
    unawaited(_sounds.playMessage());
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sounds.dispose());
    super.dispose();
  }
}
