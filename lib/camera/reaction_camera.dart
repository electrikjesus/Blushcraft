import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

typedef AudioChunkHandler = void Function(Uint8List bytes);

/// Front-camera + mic for live partner view, with privacy toggles.
class ReactionAvController extends ChangeNotifier {
  CameraController? _controller;
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  StreamSubscription<Uint8List>? _micSub;
  bool initializing = false;
  String? error;
  bool cameraPermissionDenied = false;
  bool micPermissionDenied = false;

  bool cameraEnabled = false;
  bool micEnabled = false;
  bool peerCameraEnabled = false;
  bool peerMicEnabled = false;

  AudioChunkHandler? onLocalAudioChunk;

  CameraController? get controller => _controller;
  bool get ready => _controller?.value.isInitialized == true;
  bool get showPreview => ready && cameraEnabled;

  Future<bool> init() async {
    if (ready || initializing) return ready;
    initializing = true;
    error = null;
    notifyListeners();

    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    cameraPermissionDenied = !cam.isGranted;
    micPermissionDenied = !mic.isGranted;

    if (!cam.isGranted) {
      error = 'Camera permission denied';
      initializing = false;
      notifyListeners();
      return false;
    }

    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      _controller = ctrl;
    } catch (e) {
      error = 'Camera error: $e';
      _controller = null;
    }

    initializing = false;
    notifyListeners();

    if (micEnabled && !micPermissionDenied) {
      await startMic();
    }
    return ready;
  }

  Future<void> setCameraEnabled(bool enabled) async {
    if (cameraEnabled == enabled) return;
    cameraEnabled = enabled;
    notifyListeners();
  }

  Future<void> setMicEnabled(bool enabled) async {
    if (micEnabled == enabled) return;
    micEnabled = enabled;
    if (enabled) {
      final mic = await Permission.microphone.request();
      micPermissionDenied = !mic.isGranted;
      if (!micPermissionDenied) {
        await startMic();
      }
    } else {
      await stopMic();
    }
    notifyListeners();
  }

  void setPeerPrivacy({required bool cameraOn, required bool micOn}) {
    peerCameraEnabled = cameraOn;
    peerMicEnabled = micOn;
    notifyListeners();
  }

  Future<void> startMic() async {
    if (micPermissionDenied || !micEnabled) return;
    try {
      if (await _recorder.isRecording()) return;
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        micPermissionDenied = true;
        notifyListeners();
        return;
      }

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 24000,
      );
      final stream = await _recorder.startStream(config);
      await _micSub?.cancel();
      _micSub = stream.listen((chunk) {
        if (!micEnabled) return;
        if (chunk.isEmpty) return;
        onLocalAudioChunk?.call(chunk);
      });
    } catch (e) {
      debugPrint('mic start error: $e');
    }
  }

  Future<void> stopMic() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
  }

  bool _playing = false;

  Future<void> playPeerAudio(Uint8List bytes) async {
    if (!peerMicEnabled || bytes.isEmpty) return;
    if (_playing) return; // drop backlog rather than stacking latency
    _playing = true;
    try {
      await _player.stop();
      await _player.play(BytesSource(bytes, mimeType: 'audio/aac'));
      await _player.onPlayerComplete.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('peer audio play error: $e');
    } finally {
      _playing = false;
    }
  }

  Future<String?> captureBase64Jpeg() async {
    if (!ready || !cameraEnabled) return null;
    try {
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('capture error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    unawaited(stopMic());
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }
}
