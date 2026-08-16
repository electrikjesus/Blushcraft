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

enum _JoinPhase { scanInvite, showAnswer, waiting }

/// Guest scans the host invite one code at a time, then shows answer codes.
class OnlineJoinQrScreen extends StatefulWidget {
  const OnlineJoinQrScreen({
    super.key,
    required this.session,
    required this.onCancel,
    required this.onConnected,
  });

  final WebRtcQrSession session;
  final VoidCallback onCancel;
  final VoidCallback onConnected;

  @override
  State<OnlineJoinQrScreen> createState() => _OnlineJoinQrScreenState();
}

class _OnlineJoinQrScreenState extends State<OnlineJoinQrScreen> {
  final _offerController = TextEditingController();
  final _inviteBag = QrChunkBag();
  MobileScannerController? _scannerController;
  String? _error;
  bool _busy = false;
  bool _cameraAvailable = false;
  bool _flashCheck = false;
  List<String> _answerChunks = const [];
  int _chunkIndex = 0;
  _JoinPhase _phase = _JoinPhase.scanInvite;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    WakelockPlus.enable();
    _probeCamera();
  }

  Future<void> _probeCamera() async {
    final ok = await deviceHasUsableCamera();
    if (!mounted) return;
    setState(() => _cameraAvailable = ok);
    if (!ok) {
      blushLog('RTC', 'join: no camera — paste-only invite');
    } else {
      await _openScanner();
    }
  }

  void _onSession() {
    if (widget.session.isConnected && mounted) {
      widget.onConnected();
      return;
    }
    if (!mounted) return;
    final err = widget.session.lastError;
    setState(() {
      if (err != null) _error = err;
      if ((widget.session.status ?? '').startsWith('Connecting')) {
        _phase = _JoinPhase.waiting;
      }
    });
  }

  Future<void> _openScanner() async {
    if (!_cameraAvailable) return;
    _scannerController ??= MobileScannerController();
    try {
      await _scannerController!.start();
      if (mounted) setState(() {});
    } catch (e) {
      blushLog('RTC', 'scanner start failed: $e');
      setState(() {
        _error = 'Scanner unavailable — paste the invite text instead.';
      });
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _offerController.dispose();
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

  Future<void> _handleScanned(String value) async {
    if (_busy || _phase != _JoinPhase.scanInvite) return;
    final added = _inviteBag.add(value);
    if (!added) return;
    blushLog(
      'RTC',
      'guest scanned invite part ${_inviteBag.haveCount}/${_inviteBag.totalCount}',
    );
    if (_inviteBag.isComplete) {
      await _flashThen(() {
        _acceptOffer(_inviteBag.join());
      });
      return;
    }
    await _flashThen(() {
      setState(() => _error = null);
    });
  }

  Future<void> _acceptOffer(String raw) async {
    if (_busy || widget.session.answerPayload != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      try {
        await _scannerController?.stop();
      } catch (_) {}
      blushLog('RTC', 'guest acceptOffer chars=${raw.length}');
      final answer = await widget.session.acceptOfferAndCreateAnswer(raw);
      final chunks = SdpQrCodec.chunk(answer);
      blushLog('RTC', 'guest answer ready chunks=${chunks.length}');
      setState(() {
        _answerChunks = chunks;
        _chunkIndex = 0;
        _phase = _JoinPhase.showAnswer;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _inviteBag.parts.clear();
        _inviteBag.expectedTotal = null;
        _phase = _JoinPhase.scanInvite;
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
          title: const Text('Join online'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: widget.onCancel,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_phase == _JoinPhase.scanInvite)
              _scanInvite()
            else if (_phase == _JoinPhase.showAnswer)
              _showAnswer()
            else
              _waiting(),
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
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

  Widget _scanInvite() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PairingStepHeader(
          step: 1,
          stepCount: 2,
          title: 'Scan their invite',
          hint: _cameraAvailable
              ? 'Point at the invite codes on the host’s screen, one at a time. '
                  'A green check means that code is locked in.'
              : 'Paste the full invite text they copied or shared.',
        ),
        const SizedBox(height: 16),
        if (_inviteBag.totalCount > 1)
          QrPartPips(
            total: _inviteBag.totalCount,
            current: (_inviteBag.haveCount + 1).clamp(1, _inviteBag.totalCount),
            completed: _inviteBag.parts.keys.toSet(),
            label: 'Invite',
            assumePreviousDone: false,
          ),
        if (_inviteBag.haveCount > 0) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              _inviteBag.isComplete
                  ? 'Invite complete'
                  : 'Got ${_inviteBag.haveCount} of ${_inviteBag.totalCount} — scan the next code',
              style: BlushTheme.body(
                14,
                weight: FontWeight.w600,
                color: const Color(0xFF3D9A6A),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_cameraAvailable && _scannerController != null)
          PairingScannerPane(
            controller: _scannerController!,
            flashCheck: _flashCheck,
            onDetect: _handleScanned,
          ),
        const SizedBox(height: 20),
        Text(
          'Or paste the full invite',
          style: BlushTheme.body(13, color: BlushTheme.inkMuted),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _offerController,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Paste full BC1:… invite',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _pasteInvite,
                child: const Text('Paste'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _acceptOffer(_offerController.text.trim()),
                child: const Text('Use invite'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _showAnswer() {
    if (_answerChunks.isEmpty) {
      return Text(
        widget.session.status ?? 'Preparing answer…',
        style: BlushTheme.body(14, color: BlushTheme.inkMuted),
      );
    }
    final last = _chunkIndex >= _answerChunks.length - 1;
    final payload = _answerChunks[_chunkIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PairingStepHeader(
          step: 2,
          stepCount: 2,
          title: 'Show this answer',
          hint: _answerChunks.length == 1
              ? 'The host scans this one code. Keep this screen awake until you connect.'
              : 'The host scans this code, then you tap Next. '
                  '${_answerChunks.length} answer codes to show.',
        ),
        const SizedBox(height: 8),
        Text(
          widget.session.status ?? '',
          style: BlushTheme.body(13, color: BlushTheme.roseDeep),
        ),
        const SizedBox(height: 20),
        QrPartPips(
          total: _answerChunks.length,
          current: _chunkIndex + 1,
        ),
        const SizedBox(height: 16),
        Center(
          child: QrCodeCard(
            data: payload,
            confirmed: last && _phase == _JoinPhase.waiting,
          ),
        ),
        const SizedBox(height: 24),
        if (!last)
          BigNextButton(
            label: 'Next code',
            onPressed: () => setState(() => _chunkIndex++),
          )
        else ...[
          Text(
            'This is the last answer code. Keep it on screen until the host scans it.',
            textAlign: TextAlign.center,
            style: BlushTheme.body(15, weight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Icon(Icons.check_circle, color: Color(0xFF3D9A6A), size: 36),
          ),
        ],
        if (_chunkIndex > 0) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _chunkIndex--),
            child: const Text('Previous code'),
          ),
        ],
        const SizedBox(height: 16),
        _shareRow(widget.session.answerPayload, kind: 'answer'),
      ],
    );
  }

  Widget _waiting() {
    return Column(
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.check_circle, color: Color(0xFF3D9A6A), size: 72),
        const SizedBox(height: 16),
        Text('Answer shown', style: BlushTheme.display(26)),
        const SizedBox(height: 8),
        Text(
          'Waiting for the host to finish connecting. Keep this app open.',
          textAlign: TextAlign.center,
          style: BlushTheme.body(15, color: BlushTheme.inkMuted),
        ),
        const SizedBox(height: 24),
        if (_busy) const CircularProgressIndicator(),
        TextButton(
          onPressed: () {
            setState(() => _phase = _JoinPhase.showAnswer);
          },
          child: const Text('Show answer codes again'),
        ),
      ],
    );
  }

  Future<void> _pasteInvite() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _error = 'Clipboard is empty');
      return;
    }
    _offerController.text = text;
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
                  content: Text('Full $kind copied (${full.length} chars)'),
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
