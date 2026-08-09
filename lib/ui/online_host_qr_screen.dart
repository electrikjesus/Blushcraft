import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../networking/webrtc/sdp_qr_codec.dart';
import '../networking/webrtc/webrtc_qr_session.dart';
import 'theme.dart';

/// Host shows offer QR; scans/pastes guest answer to finish pairing.
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
  final _answerChunks = <String>[];
  final _scannerController = MobileScannerController();
  String? _error;
  bool _busy = false;
  bool _showScanner = false;
  List<String> _offerChunks = const [];
  int _chunkIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    WakelockPlus.enable();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final offer = await widget.session.startAsHost();
      final chunks = SdpQrCodec.chunk(offer);
      setState(() {
        _offerChunks = chunks;
        _chunkIndex = 0;
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
    setState(() {
      if (err != null) _error = err;
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _answerController.dispose();
    _scannerController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _handleScannedAnswer(String value) async {
    final text = value.trim();
    if (text.startsWith('BC1C:')) {
      if (_answerChunks.contains(text)) return;
      _answerChunks.add(text);
      try {
        final joined = SdpQrCodec.joinChunks(_answerChunks);
        _answerController.text = joined;
        await _submitAnswer(joined);
      } catch (_) {
        setState(() {
          _error = 'Scanned ${_answerChunks.length} answer part(s)…';
        });
      }
      return;
    }
    if (text.contains('BC1:')) {
      _answerController.text = text;
      await _submitAnswer(text);
    }
  }

  Future<void> _submitAnswer([String? rawOverride]) async {
    final raw = (rawOverride ?? _answerController.text).trim();
    if (raw.isEmpty) return;
    if (_busy || widget.session.isConnected) return;
    setState(() {
      _busy = true;
      _error = null;
      _showScanner = false;
    });
    try {
      await _scannerController.stop();
      await widget.session.acceptAnswer(raw);
    } catch (e) {
      setState(() {
        _error = '$e';
        _answerChunks.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = _offerChunks.isEmpty
        ? null
        : _offerChunks[_chunkIndex.clamp(0, _offerChunks.length - 1)];
    final connecting = (widget.session.status ?? '').startsWith('Connecting');

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
            Text('Invite with QR', style: BlushTheme.display(28)),
            const SizedBox(height: 8),
            Text(
              'Shorter data-only invites — your partner scans this (or you share '
              'the text). Keep this screen awake until you connect. Best on Wi‑Fi.',
              style: BlushTheme.body(14, color: BlushTheme.inkMuted),
            ),
            const SizedBox(height: 8),
            Text(
              widget.session.status ?? '',
              style: BlushTheme.body(13, color: BlushTheme.roseDeep),
            ),
            const SizedBox(height: 20),
            if (_busy && payload == null)
              const Center(child: CircularProgressIndicator())
            else if (payload != null) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: payload,
                    size: 240,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
              if (_offerChunks.length > 1) ...[
                const SizedBox(height: 12),
                Text(
                  'Part ${_chunkIndex + 1} of ${_offerChunks.length}',
                  textAlign: TextAlign.center,
                  style: BlushTheme.body(13),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _chunkIndex > 0
                          ? () => setState(() => _chunkIndex--)
                          : null,
                      child: const Text('Previous'),
                    ),
                    TextButton(
                      onPressed: _chunkIndex < _offerChunks.length - 1
                          ? () => setState(() => _chunkIndex++)
                          : null,
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final full = widget.session.offerPayload;
                        if (full == null) return;
                        Clipboard.setData(
                          ClipboardData(text: SdpQrCodec.clipboardText(full)),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Full invite copied'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final full = widget.session.offerPayload;
                        if (full == null) return;
                        final text = SdpQrCodec.clipboardText(full);
                        SharePlus.instance.share(
                          ShareParams(
                            text: 'Blushcraft invite:\n$text',
                            subject: 'Blushcraft invite',
                          ),
                        );
                      },
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            Text('Their answer', style: BlushTheme.display(20)),
            const SizedBox(height: 8),
            Text(
              'Same Wi‑Fi works best. Prefer Local play (no codes) when you can. '
              'Scan their answer QR, or paste the full answer text below.',
              style: BlushTheme.body(13, color: BlushTheme.inkMuted),
            ),
            const SizedBox(height: 12),
            if (!connecting) ...[
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _showScanner = !_showScanner);
                        if (_showScanner) {
                          await _scannerController.start();
                        } else {
                          await _scannerController.stop();
                        }
                      },
                icon: Icon(_showScanner ? Icons.close : Icons.qr_code_scanner),
                label: Text(_showScanner ? 'Hide scanner' : 'Scan answer QR'),
              ),
              if (_showScanner) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 220,
                    child: MobileScanner(
                      controller: _scannerController,
                      onDetect: (capture) {
                        final barcodes = capture.barcodes;
                        if (barcodes.isEmpty) return;
                        final v = barcodes.first.rawValue;
                        if (v != null) {
                          _handleScannedAnswer(v);
                        }
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _answerController,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Paste full BC1:… answer (or all BC1C: lines)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final data =
                                  await Clipboard.getData(Clipboard.kTextPlain);
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
                            },
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
            ] else ...[
              const SizedBox(height: 8),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              Text(
                'Finishing the peer connection… keep the app open.',
                textAlign: TextAlign.center,
                style: BlushTheme.body(14, color: BlushTheme.inkMuted),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: BlushTheme.body(13, color: BlushTheme.roseDeep),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
