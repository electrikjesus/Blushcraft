import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Soft in-game chat cues (not OS notifications).
class ChatSoundPlayer {
  ChatSoundPlayer() {
    _player.setReleaseMode(ReleaseMode.stop);
    _player.setVolume(0.55);
  }

  final AudioPlayer _player = AudioPlayer();
  bool _busy = false;

  Future<void> playMessage() => _play('sounds/chat_message.wav');

  Future<void> playInvite() => _play('sounds/chat_invite.wav');

  Future<void> _play(String asset) async {
    if (_busy) return;
    _busy = true;
    try {
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (e) {
      debugPrint('chat sound error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() => _player.dispose();
}
