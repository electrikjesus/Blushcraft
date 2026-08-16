import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../networking/webrtc/sdp_qr_codec.dart';
import '../networking/webrtc/webrtc_qr_session.dart';
import '../util/blush_log.dart';
import '../util/camera_availability.dart';
import 'theme.dart';
import 'widgets/qr_pairing_chrome.dart';

enum _HostPhase { showInvite, scanAnswer, connecting }

/// Host shows offer QR one code at a time, then scans the guest answer.
class OnlineHostQrScreen extends StatefulWidget {
  const OnlineHostQrScreen({
    super.key,
    required this.session,
    required this.onCancel,
    required this.onConnected,
  });

  final WebRtcQrSession session;
  final VoidCallback onCancel;
  final VoidCallback onConnected;

  @override
  State<OnlineHostQrScreen> createState() => _OnlineHostQrScreenState();
}

class _OnlineHostQrScreenState extends State<OnlineHostQrScreen> {
  final _answerController = TextEditingController();
  final _answerBag = QrChunkBag();
  MobileScannerController? _scannerController;
  String? _error;
  bool _busy = false;
  bool _cameraAvailable = false;
  bool _flashCheck = false;
  List<String> _offerChunks = const [];
  int _chunkIndex = 0;
  _HostPhase _phase = _HostPhase.showInvite;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    WakelockPlus.enable();
    _probeCamera();
    _bootstrap();
  }

  Future<void> _probeCamera() async {
    final ok = await deviceHasUsableCamera();
    if (!mounted) return;
    setState(() => _cameraAvailable = ok);
    if (!ok) {
      blushLog('RTC', 'host: no camera — paste-only answer');
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final offer = await widget.session.startAsHost();
      final chunks = SdpQrCodec.chunk(offer);
      blushLog('RTC', 'host offer chunks=${chunks.length} chars=${offer.length}');
      setState(() {
        _offerChunks = chunks;
        _chunkIndex = 0;
        _phase = _HostPhase.showInvite;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onSession() {
    if (widget.session.isConnected && mounted) {
      widget.onConnected();
      return;
    }
    if (!mounted) return;
    final err = widget.session.lastError;
    final connecting = (widget.session.status ?? '').startsWith('Connecting');
    setState(() {
      if (err != null) _error = err;
      if (connecting) _phase = _HostPhase.connecting;
    });
  }

  Future<void> _openScanner() async {
    if (!_cameraAvailable) {
      setState(() {
        _error = 'No camera on this device — paste the answer text instead.';
      });
      return;
    }
    _scannerController ??= MobileScannerController();
    try {
      await _scannerController!.start();
    } catch (e) {
      blushLog('RTC', 'scanner start failed: $e');
      setState(() {
        _error = 'Scanner unavailable — paste the answer text instead.';
      });
    }
  }

  Future<void> _goScanAnswer() async {
    setState(() {
      _phase = _HostPhase.scanAnswer;
      _error = null;
    });
    await _openScanner();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _answerController.dispose();
    _scannerController?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _flashThen(VoidCallback next) async {
    setState(() => _flashCheck = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _flashCheck = false);
    next();
  }

  Future<void> _handleScannedAnswer(String value) async {
    if (_busy || _phase != _HostPhase.scanAnswer) return;
    final added = _answerBag.add(value);
    if (!added) return;
    blushLog(
      'RTC',
      'host scanned answer part ${_answerBag.haveCount}/${_answerBag.totalCount}',
    );
    if (_answerBag.isComplete) {
      await _flashThen(() {
        _submitAnswer(_answerBag.join());
      });
      return;
    }
    await _flashThen(() {
      setState(() {
        _error = null;
      });
    });
  }

  Future<void> _submitAnswer([String? rawOverride]) async {
    final raw = (rawOverride ?? _answerController.text).trim();
    if (raw.isEmpty) return;
    if (_busy || widget.session.isConnected) return;
    setState(() {
      _busy = true;
      _error = null;
      _phase = _HostPhase.connecting;
    });
    try {
      try {
        await _scannerController?.stop();
      } catch (_) {}
      blushLog('RTC', 'host acceptAnswer chars=${raw.length}');
      await widget.session.acceptAnswer(raw);
    } catch (e) {
      setState(() {
        _error = '$e';
        _answerBag.parts.clear();
        _answerBag.expectedTotal = null;
        _phase = _HostPhase.scanAnswer;
      });
      await _openScanner();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlushBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Host online'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: widget.onCancel,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_busy && _offerChunks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_phase == _HostPhase.showInvite)
              _showInvite()
            else if (_phase == _HostPhase.scanAnswer)
              _scanAnswer()
            else
              _connecting(),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: BlushTheme.body(14, color: BlushTheme.roseDeep),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _showInvite() {
    if (_offerChunks.isEmpty) {
      return Text(
        widget.session.status ?? 'Preparing invite…',
        style: BlushTheme.body(14, color: BlushTheme.inkMuted),
      );
    }
    final last = _chunkIndex >= _offerChunks.length - 1;
    final payload = _offerChunks[_chunkIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PairingStepHeader(
          step: 1,
          stepCount: 2,
          title: 'Show this code',
          hint: _offerChunks.length == 1
              ? 'Your partner opens Join online and scans this one code. '
                  'When they say they are done, continue.'
              : 'Your partner scans this code, then you tap Next for the '
                  'following code. ${_offerChunks.length} codes in this invite.',
        ),
        const SizedBox(height: 8),
        Text(
          widget.session.status ?? '',
          style: BlushTheme.body(13, color: BlushTheme.roseDeep),
        ),
        const SizedBox(height: 20),
        QrPartPips(
          total: _offerChunks.length,
          current: _chunkIndex + 1,
        ),
        const SizedBox(height: 16),
        Center(child: QrCodeCard(data: payload)),
        const SizedBox(height: 24),
        BigNextButton(
          label: last
              ? (_offerChunks.length > 1
                  ? 'All codes shown — scan their answer'
                  : 'Partner scanned it — scan their answer')
              : 'Next code',
          onPressed: last
              ? _goScanAnswer
              : () => setState(() => _chunkIndex++),
        ),
        if (_chunkIndex > 0) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _chunkIndex--),
            child: const Text('Previous code'),
          ),
        ],
        const SizedBox(height: 16),
        _shareRow(widget.session.offerPayload, kind: 'invite'),
      ],
    );
  }

  Widget _scanAnswer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PairingStepHeader(
          step: 2,
          stepCount: 2,
          title: 'Scan their answer',
          hint: _cameraAvailable
              ? 'Point at the answer codes on your partner’s screen, one at a time. '
                  'A green check means that code is locked in.'
              : 'Paste the full answer text they copied or shared.',
        ),
        const SizedBox(height: 16),
        if (_answerBag.totalCount > 1)
          QrPartPips(
            total: _answerBag.totalCount,
            current: (_answerBag.haveCount + 1).clamp(1, _answerBag.totalCount),
            completed: _answerBag.parts.keys.toSet(),
            label: 'Answer',
            assumePreviousDone: false,
          ),
        if (_answerBag.haveCount > 0 && _answerBag.totalCount <= 1) ...[
          const SizedBox(height: 8),
          const Center(child: _InlineCheck(label: 'Answer captured')),
        ],
        const SizedBox(height: 16),
        if (_cameraAvailable && _scannerController != null)
          PairingScannerPane(
            controller: _scannerController!,
            flashCheck: _flashCheck,
            onDetect: _handleScannedAnswer,
          )
        else if (_cameraAvailable)
          OutlinedButton.icon(
            onPressed: _openScanner,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Open camera'),
          ),
        const SizedBox(height: 20),
        Text(
          'Or paste the full answer',
          style: BlushTheme.body(13, color: BlushTheme.inkMuted),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _answerController,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Paste full BC1:… answer',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _pasteAnswer,
                child: const Text('Paste'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : () => _submitAnswer(),
                child: const Text('Connect'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _connecting() {
    return const Padding(
      padding: EdgeInsets.only(top: 48),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text(
            'Connecting… keep both apps open.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _pasteAnswer() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _error = 'Clipboard is empty');
      return;
    }
    _answerController.text = text;
    try {
      final preview = SdpQrCodec.describeEnvelope(
        SdpQrCodec.decodeEnvelope(text),
      );
      setState(() => _error = 'Ready: $preview');
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Widget _shareRow(String? full, {required String kind}) {
    if (full == null) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: SdpQrCodec.clipboardText(full)),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Full $kind copied (${full.length} chars)',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy full'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              final text = SdpQrCodec.clipboardText(full);
              SharePlus.instance.share(
                ShareParams(
                  text: 'Blushcraft $kind:\n$text',
                  subject: 'Blushcraft $kind',
                ),
              );
            },
            icon: const Icon(Icons.ios_share),
            label: const Text('Share'),
          ),
        ),
      ],
    );
  }
}

class _InlineCheck extends StatelessWidget {
  const _InlineCheck({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF3D9A6A)),
        const SizedBox(width: 8),
        Text(label, style: BlushTheme.body(15, weight: FontWeight.w600)),
      ],
    );
  }
}
