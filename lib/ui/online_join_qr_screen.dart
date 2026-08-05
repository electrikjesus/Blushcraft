import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../networking/webrtc/sdp_qr_codec.dart';
import '../networking/webrtc/webrtc_qr_session.dart';
import 'theme.dart';

/// Guest scans/pastes host offer, then shows answer QR for the host.
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
  final _chunks = <String>[];
  String? _error;
  bool _busy = false;
  bool _showScanner = true;
  List<String> _answerChunks = const [];
  int _chunkIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  void _onSession() {
    if (widget.session.isConnected && mounted) {
      widget.onConnected();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _offerController.dispose();
    super.dispose();
  }

  Future<void> _handleScanned(String value) async {
    final text = value.trim();
    if (text.startsWith('BC1C:')) {
      if (_chunks.contains(text)) return;
      _chunks.add(text);
      try {
        final joined = SdpQrCodec.joinChunks(_chunks);
        await _acceptOffer(joined);
      } catch (_) {
        // Wait for more chunks.
        setState(() {
          _error = 'Scanned ${_chunks.length} part(s)…';
        });
      }
      return;
    }
    if (text.contains('BC1:')) {
      await _acceptOffer(text);
    }
  }

  Future<void> _acceptOffer(String raw) async {
    if (_busy || widget.session.answerPayload != null) return;
    setState(() {
      _busy = true;
      _error = null;
      _showScanner = false;
    });
    try {
      final answer = await widget.session.acceptOfferAndCreateAnswer(raw);
      setState(() {
        _answerChunks = SdpQrCodec.chunk(answer);
        _chunkIndex = 0;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _showScanner = true;
        _chunks.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answer = widget.session.answerPayload;
    final payload = _answerChunks.isEmpty
        ? null
        : _answerChunks[_chunkIndex.clamp(0, _answerChunks.length - 1)];

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
            Text(
              answer == null ? 'Scan host invite' : 'Show answer to host',
              style: BlushTheme.display(28),
            ),
            const SizedBox(height: 8),
            Text(
              answer == null
                  ? 'Scan their QR or paste the invite text. Then show your answer QR back.'
                  : 'Have the host scan this (or paste the answer on their phone).',
              style: BlushTheme.body(14, color: BlushTheme.inkMuted),
            ),
            const SizedBox(height: 8),
            Text(
              widget.session.status ?? '',
              style: BlushTheme.body(13, color: BlushTheme.roseDeep),
            ),
            const SizedBox(height: 16),
            if (answer == null) ...[
              if (_showScanner)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 240,
                    child: MobileScanner(
                      onDetect: (capture) {
                        final barcodes = capture.barcodes;
                        if (barcodes.isEmpty) return;
                        final v = barcodes.first.rawValue;
                        if (v != null) {
                          _handleScanned(v);
                        }
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _offerController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Or paste BC1:… invite here',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _acceptOffer(_offerController.text.trim()),
                child: const Text('Use pasted invite'),
              ),
            ] else ...[
              if (payload != null)
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
                    ),
                  ),
                ),
              if (_answerChunks.length > 1) ...[
                const SizedBox(height: 12),
                Text(
                  'Part ${_chunkIndex + 1} of ${_answerChunks.length}',
                  textAlign: TextAlign.center,
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
                      onPressed: _chunkIndex < _answerChunks.length - 1
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
                        Clipboard.setData(ClipboardData(text: answer));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Answer copied')),
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
                        SharePlus.instance.share(
                          ShareParams(
                            text: 'Blushcraft answer:\n$answer',
                            subject: 'Blushcraft answer',
                          ),
                        );
                      },
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Waiting for the host to finish connecting…',
                textAlign: TextAlign.center,
                style: BlushTheme.body(14, color: BlushTheme.inkMuted),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
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
