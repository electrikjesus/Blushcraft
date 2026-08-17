import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../util/blush_log.dart';

typedef AudioChunkHandler = void Function(Uint8List bytes, String mime);

/// Front-camera + mic for live partner view, with privacy toggles.
class ReactionAvController extends ChangeNotifier {
  CameraController? _controller;
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  StreamSubscription<Uint8List>? _micSub;
  Timer? _audioFlushTimer;
  final BytesBuilder _audioOut = BytesBuilder(copy: false);
  bool initializing = false;
  bool initialized = false;
  String? error;
  bool cameraPermissionDenied = false;
  bool micPermissionDenied = false;

  bool cameraEnabled = false;
  bool micEnabled = false;
  bool peerCameraEnabled = false;
  bool peerMicEnabled = false;

  /// Local wants the mutual live media strip during play.
  bool liveViewEnabled = false;

  /// Peer also wants the mutual live media strip.
  bool peerLiveViewEnabled = false;

  /// This device has a usable camera (Camera2 probe).
  bool deviceHasCamera = true;

  /// Peer reported a usable camera (from [AvPrivacyMessage.hasCamera]).
  bool peerHasCamera = true;

  /// Local mic input level 0–1 (from recorder amplitude).
  double localAudioLevel = 0;

  /// Spectrum / level UI ticks — do **not** rebuild the whole game tree.
  /// [ReactionAvPanel] listens here; camera/mic flag changes use [notifyListeners].
  final ChangeNotifier spectrumListenable = ChangeNotifier();

  /// When false, mic is "on" for privacy/WebRTC but we do not open [AudioRecorder]
  /// (Online owns the mic via getUserMedia).
  bool localMicCapture = true;

  /// Peer's reported mic level 0–1 (from [AvPrivacyMessage.audioLevel]).
  double peerReportedAudioLevel = 0;

  /// Recent inbound stream activity 0–1 (decays when packets stop).
  double peerReceiveLevel = 0;

  /// Multi-band EQ meter values 0–1 (bass → treble).
  static const spectrumBandCount = 8;
  final List<double> localSpectrum =
      List<double>.filled(spectrumBandCount, 0, growable: false);
  final List<double> peerSpectrum =
      List<double>.filled(spectrumBandCount, 0, growable: false);
  double localPeak = 0;
  double peerPeak = 0;

  bool _capturing = false;
  String _audioMime = 'audio/aac';
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _peerReceiveDecay;
  Timer? _spectrumTick;
  DateTime? _lastPeerLevelAt;
  double _prevLocalLevel = 0;
  double _prevPeerLevel = 0;

  /// Playback queue — play sequentially instead of dropping while busy.
  final List<({Uint8List bytes, String mime})> _playQueue = [];
  bool _playing = false;
  static const _maxPlayQueue = 6;

  int _audioSendSeq = 0;
  int _audioRecvSeq = 0;
  int _audioDropOldest = 0;
  int _audioPlayErrors = 0;
  int _audioPlayTimeouts = 0;
  DateTime? _lastAudioSendLog;
  DateTime? _lastAudioRecvLog;

  AudioChunkHandler? onLocalAudioChunk;

  CameraController? get controller => _controller;
  bool get ready => _controller?.value.isInitialized == true;
  bool get showPreview => ready && cameraEnabled;

  /// Both sides opted into the live media panel.
  bool get bothLiveViewEnabled => liveViewEnabled && peerLiveViewEnabled;

  /// Prefer audio-only UI when either device lacks a camera.
  bool get audioOnlyLiveMedia =>
      bothLiveViewEnabled && (!deviceHasCamera || !peerHasCamera);

  Future<void> setDeviceHasCamera(bool value) async {
    if (deviceHasCamera == value) return;
    deviceHasCamera = value;
    if (!value && cameraEnabled) {
      await setCameraEnabled(false);
    }
    notifyListeners();
  }

  Future<void> setLiveViewEnabled(bool enabled) async {
    if (liveViewEnabled == enabled) return;
    liveViewEnabled = enabled;
    notifyListeners();
  }

  void setPeerPrivacy({
    required bool cameraOn,
    required bool micOn,
    bool? liveViewOn,
    bool? hasCamera,
    double? audioLevel,
  }) {
    var flagsChanged = peerCameraEnabled != cameraOn || peerMicEnabled != micOn;
    peerCameraEnabled = cameraOn;
    peerMicEnabled = micOn;
    if (liveViewOn != null && peerLiveViewEnabled != liveViewOn) {
      peerLiveViewEnabled = liveViewOn;
      flagsChanged = true;
    }
    if (hasCamera != null && peerHasCamera != hasCamera) {
      peerHasCamera = hasCamera;
      flagsChanged = true;
    }
    if (audioLevel != null) {
      peerReportedAudioLevel = audioLevel.clamp(0.0, 1.0);
      _lastPeerLevelAt = DateTime.now();
      _ensureSpectrumTick();
      spectrumListenable.notifyListeners();
    }
    if (flagsChanged) notifyListeners();
  }

  /// Display level for partner chip: reported mic, boosted by receive pulse.
  double get peerDisplayAudioLevel {
    if (!peerMicEnabled) return 0;
    return peerReportedAudioLevel > peerReceiveLevel
        ? peerReportedAudioLevel
        : peerReceiveLevel;
  }

  double get localDisplayAudioLevel => micEnabled ? localAudioLevel : 0;

  List<double> get localDisplaySpectrum =>
      micEnabled ? localSpectrum : const [0, 0, 0, 0, 0, 0, 0, 0];

  List<double> get peerDisplaySpectrum =>
      peerMicEnabled ? peerSpectrum : const [0, 0, 0, 0, 0, 0, 0, 0];

  void _ensureSpectrumTick() {
    if (_spectrumTick != null) return;
    _spectrumTick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final localActive = micEnabled && _localSpectrumDriveLevel > 0.02;
      final peerActive = peerMicEnabled && _peerSpectrumDriveLevel > 0.02;
      if (!localActive && !peerActive) {
        var any = false;
        for (var i = 0; i < spectrumBandCount; i++) {
          if (localSpectrum[i] > 0.01 || peerSpectrum[i] > 0.01) {
            any = true;
            break;
          }
        }
        if (!any && localPeak < 0.02 && peerPeak < 0.02) {
          _spectrumTick?.cancel();
          _spectrumTick = null;
          return;
        }
      }
      if (micEnabled) {
        final level = _localSpectrumDriveLevel;
        _driveSpectrum(
          localSpectrum,
          level: level,
          prevLevel: _prevLocalLevel,
          peak: localPeak,
          onPeak: (p) => localPeak = p,
        );
        _prevLocalLevel = level;
      } else {
        _decaySpectrum(localSpectrum);
        localPeak *= 0.9;
        localAudioLevel = 0;
      }
      if (peerMicEnabled) {
        final peerLvl = _peerSpectrumDriveLevel;
        _driveSpectrum(
          peerSpectrum,
          level: peerLvl,
          prevLevel: _prevPeerLevel,
          peak: peerPeak,
          onPeak: (p) => peerPeak = p,
        );
        _prevPeerLevel = peerLvl;
      } else {
        _decaySpectrum(peerSpectrum);
        peerPeak *= 0.9;
      }
      spectrumListenable.notifyListeners();
    });
  }

  /// Soft bounce when mic is on but amplitude is owned by WebRTC (no recorder).
  double get _localSpectrumDriveLevel {
    if (!micEnabled) return 0;
    if (localMicCapture) return localAudioLevel;
    final t = DateTime.now().millisecondsSinceEpoch / 280.0;
    return 0.16 + 0.1 * math.sin(t);
  }

  /// Use peer-reported levels when fresh; otherwise soft ambient (Online).
  double get _peerSpectrumDriveLevel {
    if (!peerMicEnabled) return 0;
    final at = _lastPeerLevelAt;
    if (at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 2)) {
      return peerDisplayAudioLevel;
    }
    final t = DateTime.now().millisecondsSinceEpoch / 310.0;
    return 0.14 + 0.1 * math.sin(t + 1.7);
  }

  void _decaySpectrum(List<double> bands) {
    for (var i = 0; i < bands.length; i++) {
      bands[i] *= 0.82;
      if (bands[i] < 0.01) bands[i] = 0;
    }
  }

  /// Decorative visualizer bands — independent bounce, not a volume meter.
  void _driveSpectrum(
    List<double> bands, {
    required double level,
    required double prevLevel,
    required double peak,
    required void Function(double) onPeak,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    onPeak(math.max(peak * 0.9, level));
    final energy = level < 0.05 ? 0.0 : math.min(1.0, 0.25 + level * 0.9);

    for (var i = 0; i < bands.length; i++) {
      if (energy <= 0) {
        bands[i] *= 0.72;
        if (bands[i] < 0.02) bands[i] = 0;
        continue;
      }
      final a = math.sin(now * (5.4 + i * 2.7) + i * 1.1);
      final b = math.sin(now * (8.1 + i * 3.3) + i * 0.4);
      final c = math.sin(now * (3.2 + i * 1.6) + i * 2.0);
      final dance = 0.5 + 0.5 * a * b;
      final midBoost = 0.75 + 0.25 * math.sin((i / (bands.length - 1)) * math.pi);
      final target = (energy * (0.22 + 0.78 * dance) * midBoost +
              0.12 * energy * (0.5 + 0.5 * c))
          .clamp(0.0, 1.0);
      bands[i] += (target - bands[i]) * (target > bands[i] ? 0.55 : 0.28);
    }
  }

  String get audioMime => _audioMime;

  /// Prepare camera (if available) and/or mic. Succeeds for audio-only devices.
  ///
  /// When [openCamera] is false (LAN WebRTC owns the camera), only mic setup runs.
  Future<bool> init({bool openCamera = true}) async {
    if (initialized || initializing) return initialized || ready;
    initializing = true;
    error = null;
    notifyListeners();

    final mic = await Permission.microphone.request();
    micPermissionDenied = !mic.isGranted;

    if (openCamera && deviceHasCamera) {
      final cam = await Permission.camera.request();
      cameraPermissionDenied = !cam.isGranted;

      if (cam.isGranted) {
        try {
          final cameras = await availableCameras();
          if (cameras.isEmpty) {
            error = 'No camera available';
            _controller = null;
          } else {
            final front = cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => cameras.first,
            );
            // Mic is owned by [AudioRecorder] — do not open a second audio capture
            // on the camera (causes choppy / contended local audio).
            final ctrl = CameraController(
              front,
              ResolutionPreset.low,
              enableAudio: false,
              imageFormatGroup: ImageFormatGroup.jpeg,
            );
            await ctrl.initialize();
            _controller = ctrl;
          }
        } catch (e) {
          error = 'Camera error: $e';
          _controller = null;
        }
      } else {
        error = 'Camera permission denied';
      }
    } else {
      cameraPermissionDenied = false;
      _controller = null;
    }

    initializing = false;
    // Audio-only / WebRTC-video: count as initialized without a camera controller.
    initialized = ready ||
        !deviceHasCamera ||
        !openCamera ||
        error == 'No camera available';
    blushLog(
      'AV',
      'init done openCamera=$openCamera ready=$ready '
      'initialized=$initialized hasCam=$deviceHasCamera err=$error',
    );
    notifyListeners();

    if (micEnabled && !micPermissionDenied) {
      await startMic();
    }
    return initialized;
  }

  Future<void> setCameraEnabled(bool enabled) async {
    if (!deviceHasCamera && enabled) return;
    if (cameraEnabled == enabled) return;
    cameraEnabled = enabled;
    notifyListeners();
  }

  Future<void> setMicEnabled(
    bool enabled, {
    bool startCapture = true,
  }) async {
    localMicCapture = startCapture;
    if (micEnabled == enabled) {
      if (enabled && startCapture && !micPermissionDenied) {
        await startMic();
      } else if (enabled && !startCapture) {
        await stopMic();
        _ensureSpectrumTick();
      }
      notifyListeners();
      return;
    }
    micEnabled = enabled;
    if (enabled) {
      final mic = await Permission.microphone.request();
      micPermissionDenied = !mic.isGranted;
      if (!micPermissionDenied && startCapture) {
        await startMic();
      } else if (!micPermissionDenied && !startCapture) {
        _ensureSpectrumTick();
      }
    } else {
      await stopMic();
    }
    notifyListeners();
  }

  Future<void> startMic() async {
    if (micPermissionDenied || !micEnabled || !localMicCapture) return;
    try {
      if (await _recorder.isRecording()) return;
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        micPermissionDenied = true;
        notifyListeners();
        return;
      }

      // Prefer speech-efficient codecs at low bitrate; fall back if unsupported.
      final started = await _startMicWithConfig(
            const RecordConfig(
              encoder: AudioEncoder.opus,
              sampleRate: 16000,
              numChannels: 1,
              bitRate: 12000,
            ),
            mime: 'audio/ogg',
          ) ||
          await _startMicWithConfig(
            const RecordConfig(
              encoder: AudioEncoder.aacHe,
              sampleRate: 16000,
              numChannels: 1,
              bitRate: 16000,
            ),
            mime: 'audio/aac',
          ) ||
          await _startMicWithConfig(
            const RecordConfig(
              encoder: AudioEncoder.aacLc,
              sampleRate: 16000,
              numChannels: 1,
              bitRate: 16000,
            ),
            mime: 'audio/aac',
          );

      if (!started) {
        blushLog('Audio', 'mic start: no supported low-bitrate encoder');
      } else {
        blushLog(
          'Audio',
          'mic started mime=$_audioMime peerMic=$peerMicEnabled',
        );
      }
    } catch (e) {
      blushLog('Audio', 'mic start error: $e');
    }
  }

  Future<bool> _startMicWithConfig(
    RecordConfig config, {
    required String mime,
  }) async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      final stream = await _recorder.startStream(config);
      _audioMime = mime;
      _audioOut.clear();
      await _micSub?.cancel();
      _audioFlushTimer?.cancel();
      _micSub = stream.listen((chunk) {
        if (!micEnabled) return;
        if (chunk.isEmpty) return;
        _audioOut.add(chunk);
      });
      await _ampSub?.cancel();
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen(_onAmplitude);
      // Coalesce stream packets into ~100ms payloads so we don't drop frames
      // and so the peer gets continuous codec bitstreams.
      _audioFlushTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _flushAudioOut();
      });
      debugPrint('mic streaming mime=$mime encoder=${config.encoder}');
      blushLog('Audio', 'encoder ok mime=$mime encoder=${config.encoder}');
      return true;
    } catch (e) {
      debugPrint('mic config ${config.encoder} failed: $e');
      blushLog('Audio', 'encoder fail ${config.encoder}: $e');
      try {
        if (await _recorder.isRecording()) await _recorder.stop();
      } catch (_) {}
      return false;
    }
  }

  void _onAmplitude(Amplitude amp) {
    // dBFS: silence ~-60 or lower, speech often -30..-5.
    final next = ((amp.current + 55) / 45).clamp(0.0, 1.0);
    localAudioLevel = next;
    _ensureSpectrumTick();
    // Levels only refresh the media strip — never the whole game screen.
    spectrumListenable.notifyListeners();
  }

  void notePeerReceiveActivity(Uint8List bytes) {
    if (bytes.isEmpty) return;
    var acc = 0;
    final n = bytes.length < 128 ? bytes.length : 128;
    for (var i = 0; i < n; i++) {
      acc += bytes[i];
    }
    final avg = acc / n / 255.0;
    peerReceiveLevel = (0.2 + avg * 0.8).clamp(0.0, 1.0);
    _lastPeerLevelAt = DateTime.now();
    _ensureSpectrumTick();
    _peerReceiveDecay?.cancel();
    _peerReceiveDecay = Timer.periodic(const Duration(milliseconds: 80), (t) {
      peerReceiveLevel *= 0.72;
      if (peerReceiveLevel < 0.04) {
        peerReceiveLevel = 0;
        t.cancel();
      }
      spectrumListenable.notifyListeners();
    });
    spectrumListenable.notifyListeners();
  }

  void _flushAudioOut() {
    if (!micEnabled) {
      _audioOut.clear();
      return;
    }
    if (_audioOut.isEmpty) return;
    final bytes = _audioOut.takeBytes();
    if (bytes.isEmpty) return;
    Uint8List payload = bytes;
    var truncated = false;
    // Hard cap one payload (~0.5s of 16kbps ≈ 1KB raw; allow headroom).
    if (bytes.length > 8 * 1024) {
      final start = bytes.length - 8 * 1024;
      payload = Uint8List.sublistView(bytes, start);
      truncated = true;
    }
    _audioSendSeq++;
    final now = DateTime.now();
    final shouldLog = _lastAudioSendLog == null ||
        now.difference(_lastAudioSendLog!) > const Duration(seconds: 2) ||
        truncated;
    if (shouldLog) {
      _lastAudioSendLog = now;
      blushLog(
        'Audio',
        'flush #$_audioSendSeq bytes=${payload.length} mime=$_audioMime '
        'truncated=$truncated handler=${onLocalAudioChunk != null}',
      );
    }
    onLocalAudioChunk?.call(payload, _audioMime);
  }

  Future<void> stopMic() async {
    blushLog(
      'Audio',
      'stopMic sendSeq=$_audioSendSeq recvSeq=$_audioRecvSeq '
      'drops=$_audioDropOldest playErr=$_audioPlayErrors '
      'timeouts=$_audioPlayTimeouts q=${_playQueue.length}',
    );
    _audioFlushTimer?.cancel();
    _audioFlushTimer = null;
    await _ampSub?.cancel();
    _ampSub = null;
    _spectrumTick?.cancel();
    _spectrumTick = null;
    localAudioLevel = 0;
    localPeak = 0;
    for (var i = 0; i < localSpectrum.length; i++) {
      localSpectrum[i] = 0;
    }
    _flushAudioOut();
    await _micSub?.cancel();
    _micSub = null;
    _audioOut.clear();
    _playQueue.clear();
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> playPeerAudio(
    Uint8List bytes, {
    String mime = 'audio/aac',
  }) async {
    _audioRecvSeq++;
    if (!peerMicEnabled) {
      blushLog('Audio', 'play skip #$_audioRecvSeq peerMic=false');
      return;
    }
    if (bytes.isEmpty) {
      blushLog('Audio', 'play skip #$_audioRecvSeq empty');
      return;
    }
    notePeerReceiveActivity(bytes);
    if (_playQueue.length >= _maxPlayQueue) {
      _playQueue.removeAt(0); // drop oldest to limit latency
      _audioDropOldest++;
      blushLog(
        'Audio',
        'play queue dropOldest totalDrops=$_audioDropOldest '
        'incomingBytes=${bytes.length}',
      );
    }
    _playQueue.add((bytes: bytes, mime: mime));
    final now = DateTime.now();
    if (_lastAudioRecvLog == null ||
        now.difference(_lastAudioRecvLog!) > const Duration(seconds: 2)) {
      _lastAudioRecvLog = now;
      blushLog(
        'Audio',
        'recv #$_audioRecvSeq bytes=${bytes.length} mime=$mime '
        'q=${_playQueue.length} playing=$_playing',
      );
    }
    if (_playing) return;
    _playing = true;
    try {
      while (_playQueue.isNotEmpty && peerMicEnabled) {
        final chunk = _playQueue.removeAt(0);
        try {
          await _player.stop();
          await _player.play(
            BytesSource(chunk.bytes, mimeType: chunk.mime),
          );
          try {
            await _player.onPlayerComplete.first.timeout(
              const Duration(milliseconds: 800),
            );
          } on TimeoutException {
            _audioPlayTimeouts++;
            blushLog(
              'Audio',
              'play timeout #$_audioPlayTimeouts mime=${chunk.mime} '
              'bytes=${chunk.bytes.length}',
            );
          }
        } catch (e) {
          _audioPlayErrors++;
          blushLog('Audio', 'play error #$_audioPlayErrors: $e');
          debugPrint('peer audio play error: $e');
        }
      }
    } finally {
      _playing = false;
    }
  }

  /// Snapshot for LAN peer view / chat selfie — resized for the wire.
  Future<String?> captureBase64Jpeg({
    int maxWidth = 320,
    int quality = 55,
  }) async {
    if (!ready || !cameraEnabled) return null;
    if (_capturing) return null;
    if (_controller!.value.isTakingPicture) return null;
    _capturing = true;
    try {
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      final compressed = await compute(
        _compressJpegIsolate,
        _CompressArgs(bytes, maxWidth, quality),
      );
      if (compressed == null) return null;
      return base64Encode(compressed);
    } catch (e) {
      debugPrint('capture error: $e');
      return null;
    } finally {
      _capturing = false;
    }
  }

  @override
  void dispose() {
    _peerReceiveDecay?.cancel();
    _spectrumTick?.cancel();
    unawaited(_ampSub?.cancel());
    unawaited(stopMic());
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
    final c = _controller;
    _controller = null;
    c?.dispose();
    spectrumListenable.dispose();
    super.dispose();
  }
}

class _CompressArgs {
  const _CompressArgs(this.bytes, this.maxWidth, this.quality);
  final Uint8List bytes;
  final int maxWidth;
  final int quality;
}

Uint8List? _compressJpegIsolate(_CompressArgs args) {
  try {
    final decoded = img.decodeImage(args.bytes);
    if (decoded == null) return null;
    final resized = decoded.width > args.maxWidth
        ? img.copyResize(decoded, width: args.maxWidth)
        : decoded;
    return Uint8List.fromList(
      img.encodeJpg(resized, quality: args.quality),
    );
  } catch (_) {
    return null;
  }
}
