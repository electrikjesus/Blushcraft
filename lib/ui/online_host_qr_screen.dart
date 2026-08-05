import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

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
  String? _error;
  bool _busy = false;
  List<String> _offerChunks = const [];
  int _chunkIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
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
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _submitAnswer() async {
    final raw = _answerController.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.acceptAnswer(raw);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload =
        _offerChunks.isEmpty ? null : _offerChunks[_chunkIndex.clamp(0, _offerChunks.length - 1)];

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
              'Your partner scans this code (or you share the text). '
              'Works best on Wi-Fi. No game data leaves your phones.',
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
                        Clipboard.setData(ClipboardData(text: full));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite copied')),
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
                        SharePlus.instance.share(
                          ShareParams(
                            text: 'Blushcraft invite:\n$full',
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
            Text('Paste their answer', style: BlushTheme.display(20)),
            const SizedBox(height: 8),
            TextField(
              controller: _answerController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Paste BC1:… answer from your partner',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : _submitAnswer,
              child: const Text('Connect with answer'),
            ),
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
