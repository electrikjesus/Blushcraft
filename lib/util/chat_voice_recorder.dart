import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../state/chat_controller.dart';
import 'blush_log.dart';

/// Hold-to-record voice notes for chat (file-based, under size cap).
class ChatVoiceRecorder {
  ChatVoiceRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  DateTime? _startedAt;
  String? _path;
  String _mime = 'audio/aac';
  bool _recording = false;

  bool get isRecording => _recording;

  Future<bool> start() async {
    if (_recording) return true;
    final ok = await _recorder.hasPermission();
    if (!ok) {
      blushLog('ChatAudio', 'mic permission denied');
      return false;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/blush_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final started = await _tryStart(
          path,
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 24000,
          ),
          mime: 'audio/aac',
        ) ||
        await _tryStart(
          path,
          const RecordConfig(
            encoder: AudioEncoder.aacHe,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 16000,
          ),
          mime: 'audio/aac',
        ) ||
        await _tryStart(
          '${dir.path}/blush_voice_${DateTime.now().millisecondsSinceEpoch}.ogg',
          const RecordConfig(
            encoder: AudioEncoder.opus,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 16000,
          ),
          mime: 'audio/ogg',
        );
    if (!started) return false;
    _recording = true;
    _startedAt = DateTime.now();
    blushLog('ChatAudio', 'recording start mime=$_mime');
    return true;
  }

  Future<bool> _tryStart(
    String path,
    RecordConfig config, {
    required String mime,
  }) async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      await _recorder.start(config, path: path);
      _path = path;
      _mime = mime;
      return true;
    } catch (e) {
      blushLog('ChatAudio', 'start fail ${config.encoder}: $e');
      return false;
    }
  }

  /// Stops and returns encoded payload, or null if too short / too large / failed.
  Future<({String base64, String mime, int durationMs})?> stopAndRead() async {
    if (!_recording) return null;
    _recording = false;
    final started = _startedAt;
    _startedAt = null;
    String? path;
    try {
      path = await _recorder.stop() ?? _path;
    } catch (e) {
      blushLog('ChatAudio', 'stop error: $e');
      path = _path;
    }
    _path = null;
    final durationMs = started == null
        ? 0
        : DateTime.now().difference(started).inMilliseconds;
    if (path == null || durationMs < 400) {
      blushLog('ChatAudio', 'drop too short ${durationMs}ms');
      _deleteQuiet(path);
      return null;
    }
    try {
      final bytes = await File(path).readAsBytes();
      _deleteQuiet(path);
      if (bytes.isEmpty) return null;
      final b64 = base64Encode(bytes);
      if (b64.length > ChatController.maxBase64Chars) {
        blushLog('ChatAudio', 'drop oversized b64=${b64.length}');
        return null;
      }
      blushLog(
        'ChatAudio',
        'ready bytes=${bytes.length} b64=${b64.length} '
        'ms=$durationMs mime=$_mime',
      );
      return (base64: b64, mime: _mime, durationMs: durationMs);
    } catch (e) {
      blushLog('ChatAudio', 'read failed: $e');
      _deleteQuiet(path);
      return null;
    }
  }

  Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    _startedAt = null;
    try {
      final path = await _recorder.stop() ?? _path;
      _deleteQuiet(path);
    } catch (_) {}
    _path = null;
  }

  void _deleteQuiet(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}

/// Decode chat voice payload for playback.
Uint8List? decodeChatAudioBase64(String base64) {
  try {
    return base64Decode(base64);
  } catch (_) {
    return null;
  }
}
