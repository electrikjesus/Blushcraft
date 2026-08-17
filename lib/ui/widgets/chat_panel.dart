import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../state/chat_controller.dart';
import '../../util/chat_photo_picker.dart';
import '../../util/chat_voice_recorder.dart';
import '../adaptive.dart';
import '../theme.dart';

/// Bottom sheet peer chat: consent actions, text, and photos.
class ChatPanel {
  ChatPanel._();

  static Future<void> open(
    BuildContext context, {
    required ChatController chat,
    required String partnerName,
    Future<String?> Function()? captureReactionSelfie,
    Future<void> Function(bool recording)? onVoiceNoteRecording,
  }) {
    chat.setPanelOpen(true);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BlushTheme.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final win = BlushWindowSize.of(ctx);
        final fraction = win.heightCompact ? 0.92 : 0.72;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * fraction,
            child: _ChatPanelBody(
              chat: chat,
              partnerName: partnerName,
              captureReactionSelfie: captureReactionSelfie,
              onVoiceNoteRecording: onVoiceNoteRecording,
            ),
          ),
        );
      },
    ).whenComplete(() => chat.setPanelOpen(false));
  }

  static Future<void> promptInvite(
    BuildContext context, {
    required ChatController chat,
    required String partnerName,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: BlushTheme.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Invite to chat?', style: BlushTheme.display(22)),
              const SizedBox(height: 8),
              Text(
                'Ask $partnerName to allow chat. Nothing is sent until they Allow.',
                style: BlushTheme.body(14, color: BlushTheme.inkMuted),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Send invite'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
    if (ok == true) await chat.invitePartner();
  }
}

class ChatAppBarButton extends StatelessWidget {
  const ChatAppBarButton({
    super.key,
    required this.chat,
    required this.partnerName,
    required this.enabled,
    this.captureReactionSelfie,
    this.onVoiceNoteRecording,
  });

  final ChatController chat;
  final String partnerName;
  final bool enabled;
  final Future<String?> Function()? captureReactionSelfie;
  final Future<void> Function(bool recording)? onVoiceNoteRecording;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        if (!enabled) return const SizedBox.shrink();
        return IconButton(
          tooltip: 'Chat',
          onPressed: () async {
            if (chat.status == ChatConsentStatus.open) {
              await ChatPanel.open(
                context,
                chat: chat,
                partnerName: partnerName,
                captureReactionSelfie: captureReactionSelfie,
                onVoiceNoteRecording: onVoiceNoteRecording,
              );
            } else if (chat.status == ChatConsentStatus.inviteIncoming) {
              // Banner handles Allow; still open panel for context after accept.
              await ChatPanel.open(
                context,
                chat: chat,
                partnerName: partnerName,
                captureReactionSelfie: captureReactionSelfie,
                onVoiceNoteRecording: onVoiceNoteRecording,
              );
            } else if (chat.status == ChatConsentStatus.inviteSent) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(chat.statusHint ?? 'Waiting for partner…'),
                ),
              );
            } else {
              await ChatPanel.promptInvite(
                context,
                chat: chat,
                partnerName: partnerName,
              );
            }
          },
          icon: Badge(
            isLabelVisible: chat.unreadCount > 0 || chat.showInviteBanner,
            label: Text(
              chat.showInviteBanner
                  ? '!'
                  : (chat.unreadCount > 9 ? '9+' : '${chat.unreadCount}'),
            ),
            child: AnimatedScale(
              scale: chat.messagePulse % 2 == 0 ? 1.0 : 1.12,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                chat.status == ChatConsentStatus.open
                    ? Icons.chat_bubble
                    : Icons.chat_bubble_outline,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Non-blocking invite banner for lobby / game.
class ChatInviteBanner extends StatelessWidget {
  const ChatInviteBanner({
    super.key,
    required this.chat,
    required this.partnerName,
  });

  final ChatController chat;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) {
            return FadeTransition(
              opacity: anim,
              child: SizeTransition(
                sizeFactor: anim,
                axis: Axis.vertical,
                child: child,
              ),
            );
          },
          child: !chat.showInviteBanner
              ? const SizedBox.shrink(key: ValueKey('invite-off'))
              : Material(
                  key: ValueKey('invite-${chat.invitePulse}'),
                  color: BlushTheme.blush.withValues(alpha: 0.45),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$partnerName wants to chat',
                            style: BlushTheme.body(
                              14,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              chat.replyToInvite(accepted: false),
                          child: const Text('Not now'),
                        ),
                        ElevatedButton(
                          onPressed: () =>
                              chat.replyToInvite(accepted: true),
                          child: const Text('Allow'),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Soft in-game toast when a chat event arrives and the panel is closed.
class ChatIncomingToast extends StatefulWidget {
  const ChatIncomingToast({super.key, required this.chat});

  final ChatController chat;

  @override
  State<ChatIncomingToast> createState() => _ChatIncomingToastState();
}

class _ChatIncomingToastState extends State<ChatIncomingToast> {
  int _seenPulse = 0;
  bool _visible = false;
  String _text = '';

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_onChat);
  }

  @override
  void didUpdateWidget(covariant ChatIncomingToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat != widget.chat) {
      oldWidget.chat.removeListener(_onChat);
      widget.chat.addListener(_onChat);
    }
  }

  void _onChat() {
    final chat = widget.chat;
    if (chat.panelOpen) {
      if (_visible) setState(() => _visible = false);
      return;
    }
    final pulse = chat.messagePulse + chat.invitePulse;
    if (pulse == _seenPulse) return;
    _seenPulse = pulse;
    final hint = chat.toastHint;
    if (hint == null || hint.isEmpty) return;
    setState(() {
      _text = hint;
      _visible = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _visible = false);
      chat.clearToast();
    });
  }

  @override
  void dispose() {
    widget.chat.removeListener(_onChat);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 240),
      offset: _visible ? Offset.zero : const Offset(0, -0.4),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: _visible ? 1 : 0,
        child: _visible
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(12),
                  color: BlushTheme.cardFace,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.mark_chat_unread, color: BlushTheme.roseDeep),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: BlushTheme.body(13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _ChatPanelBody extends StatefulWidget {
  const _ChatPanelBody({
    required this.chat,
    required this.partnerName,
    this.captureReactionSelfie,
    this.onVoiceNoteRecording,
  });

  final ChatController chat;
  final String partnerName;
  final Future<String?> Function()? captureReactionSelfie;
  final Future<void> Function(bool recording)? onVoiceNoteRecording;

  @override
  State<_ChatPanelBody> createState() => _ChatPanelBodyState();
}

class _ChatPanelBodyState extends State<_ChatPanelBody> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ChatPhotoPicker();
  final _voice = ChatVoiceRecorder();
  final _player = AudioPlayer();
  bool _busy = false;
  bool _recording = false;
  String? _playingId;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    unawaited(_voice.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _sendText() async {
    final err = await widget.chat.sendText(_text.text);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    _text.clear();
    _scrollToEnd();
  }

  Future<void> _sendPicked(({String base64, String mime})? photo) async {
    if (photo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not compress photo enough to send.'),
          ),
        );
      }
      return;
    }
    final err = await widget.chat.sendPhotoBase64(
      base64Jpeg: photo.base64,
      mime: photo.mime,
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    _scrollToEnd();
  }

  Future<void> _attach(ImagePickKind kind) async {
    if (!widget.chat.canSend || _busy) return;
    setState(() => _busy = true);
    try {
      switch (kind) {
        case ImagePickKind.gallery:
          await _sendPicked(await _picker.pickGallery());
        case ImagePickKind.camera:
          await _sendPicked(await _picker.pickCamera());
        case ImagePickKind.selfie:
          final cap = widget.captureReactionSelfie;
          if (cap == null) return;
          final raw = await cap();
          if (raw == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not capture selfie.')),
              );
            }
            return;
          }
          final shrunk = await ChatPhotoPicker.shrinkBase64Jpeg(raw);
          await _sendPicked(
            shrunk == null ? null : (base64: shrunk, mime: 'image/jpeg'),
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startVoice() async {
    if (!widget.chat.canSend || _busy || _recording) return;
    setState(() {
      _busy = true;
      _recording = true;
    });
    await widget.onVoiceNoteRecording?.call(true);
    final ok = await _voice.start();
    if (!mounted) return;
    if (!ok) {
      await widget.onVoiceNoteRecording?.call(false);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _recording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission needed for voice notes.')),
      );
      return;
    }
    setState(() => _busy = false);
  }

  Future<void> _finishVoice({required bool send}) async {
    if (!_recording) return;
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      if (!send) {
        await _voice.cancel();
        return;
      }
      final clip = await _voice.stopAndRead();
      if (clip == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hold a bit longer — voice note was too short.'),
            ),
          );
        }
        return;
      }
      final err = await widget.chat.sendAudioBase64(
        base64Audio: clip.base64,
        mime: clip.mime,
        durationMs: clip.durationMs,
      );
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
      }
      _scrollToEnd();
    } finally {
      await widget.onVoiceNoteRecording?.call(false);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playVoice(ChatBubble m) async {
    final raw = m.base64Audio;
    if (raw == null || raw.isEmpty) return;
    final bytes = decodeChatAudioBase64(raw);
    if (bytes == null) return;
    try {
      if (_playingId == m.id) {
        await _player.stop();
        setState(() => _playingId = null);
        return;
      }
      await _player.stop();
      setState(() => _playingId = m.id);
      await _player.play(BytesSource(bytes, mimeType: m.mime ?? 'audio/aac'));
      await _player.onPlayerComplete.first.timeout(
        Duration(milliseconds: (m.durationMs ?? 15000) + 2000),
        onTimeout: () {},
      );
    } catch (_) {
      // Playback failures stay quiet in UI; toast if needed later.
    } finally {
      if (mounted && _playingId == m.id) {
        setState(() => _playingId = null);
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.chat,
      builder: (context, _) {
        final chat = widget.chat;
        final open = chat.status == ChatConsentStatus.open;
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: BlushTheme.inkMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chat with ${widget.partnerName}',
                      style: BlushTheme.display(20),
                    ),
                  ),
                  if (open)
                    TextButton(
                      onPressed: () async {
                        await chat.endChat();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('End'),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (chat.statusHint != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  chat.statusHint!,
                  style: BlushTheme.body(13, color: BlushTheme.roseDeep),
                ),
              ),
            if (chat.showInviteBanner)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.partnerName} invited you',
                        style: BlushTheme.body(14, weight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => chat.replyToInvite(accepted: false),
                      child: const Text('Not now'),
                    ),
                    ElevatedButton(
                      onPressed: () => chat.replyToInvite(accepted: true),
                      child: const Text('Allow'),
                    ),
                  ],
                ),
              ),
            if (chat.status == ChatConsentStatus.off ||
                chat.status == ChatConsentStatus.inviteSent)
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: chat.status == ChatConsentStatus.inviteSent
                      ? null
                      : () => chat.invitePartner(),
                  child: Text(
                    chat.status == ChatConsentStatus.inviteSent
                        ? 'Waiting for Allow…'
                        : 'Invite to chat',
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                itemCount: chat.messages.length,
                itemBuilder: (context, i) {
                  final m = chat.messages[i];
                  final mine = m.isMine(chat.localPlayerId);
                  return Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(10),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: mine ? BlushTheme.blush : BlushTheme.cardFace,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: m.kind == ChatBubbleKind.text
                          ? Text(m.text ?? '', style: BlushTheme.body(15))
                          : m.kind == ChatBubbleKind.photo
                              ? _PhotoBubble(base64: m.base64Jpeg ?? '')
                              : _AudioBubble(
                                  bubble: m,
                                  playing: _playingId == m.id,
                                  onPlay: () => _playVoice(m),
                                ),
                    ),
                  );
                },
              ),
            ),
            if (open)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_recording)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Recording… release to send, slide cancel',
                            textAlign: TextAlign.center,
                            style: BlushTheme.body(
                              12,
                              color: BlushTheme.roseDeep,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          PopupMenuButton<ImagePickKind>(
                            enabled: !_busy && !_recording,
                            tooltip: 'Attach',
                            onSelected: _attach,
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: ImagePickKind.gallery,
                                child: Text('Gallery'),
                              ),
                              const PopupMenuItem(
                                value: ImagePickKind.camera,
                                child: Text('Camera'),
                              ),
                              if (widget.captureReactionSelfie != null)
                                const PopupMenuItem(
                                  value: ImagePickKind.selfie,
                                  child: Text('Reaction selfie'),
                                ),
                            ],
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _text,
                              enabled: !_recording,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendText(),
                              decoration: const InputDecoration(
                                hintText: 'Message…',
                                isDense: true,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onLongPressStart: (_) => _startVoice(),
                            onLongPressEnd: (_) => _finishVoice(send: true),
                            onLongPressCancel: () => _finishVoice(send: false),
                            child: IconButton(
                              onPressed: null,
                              tooltip: 'Hold to record voice note',
                              icon: Icon(
                                _recording ? Icons.mic : Icons.mic_none,
                                color: _recording
                                    ? BlushTheme.roseDeep
                                    : BlushTheme.inkMuted,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _busy || _recording ? null : _sendText,
                            icon: const Icon(Icons.send),
                            color: BlushTheme.roseDeep,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum ImagePickKind { gallery, camera, selfie }

class _AudioBubble extends StatelessWidget {
  const _AudioBubble({
    required this.bubble,
    required this.playing,
    required this.onPlay,
  });

  final ChatBubble bubble;
  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final secs = ((bubble.durationMs ?? 0) / 1000).ceil().clamp(1, 99);
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            playing ? Icons.stop_circle_outlined : Icons.play_circle_fill,
            color: BlushTheme.roseDeep,
            size: 28,
          ),
          const SizedBox(width: 8),
          Text(
            playing ? 'Playing…' : 'Voice note · ${secs}s',
            style: BlushTheme.body(14, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PhotoBubble extends StatelessWidget {
  const _PhotoBubble({required this.base64});

  final String base64;

  @override
  Widget build(BuildContext context) {
    final bytes = ChatPhotoPicker.decodeJpeg(base64);
    if (bytes == null) {
      return Text('Photo unavailable', style: BlushTheme.body(13));
    }
    return GestureDetector(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          width: 180,
          height: 180,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
