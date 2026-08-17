import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../adaptive.dart';
import '../theme.dart';

/// One-step pairing chrome: progress, QR card, scan view, big Next.
class PairingStepHeader extends StatelessWidget {
  const PairingStepHeader({
    super.key,
    required this.step,
    required this.stepCount,
    required this.title,
    required this.hint,
  });

  final int step;
  final int stepCount;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step $step of $stepCount',
          style: BlushTheme.body(13, color: BlushTheme.roseDeep),
        ),
        const SizedBox(height: 6),
        Text(title, style: BlushTheme.display(26)),
        const SizedBox(height: 8),
        Text(
          hint,
          style: BlushTheme.body(15, color: BlushTheme.inkMuted),
        ),
      ],
    );
  }
}

class QrPartPips extends StatelessWidget {
  const QrPartPips({
    super.key,
    required this.total,
    required this.current,
    this.completed = const {},
    this.label = 'Code',
    this.assumePreviousDone = true,
  });

  final int total;
  final int current;
  final Set<int> completed;
  final String label;
  final bool assumePreviousDone;

  @override
  Widget build(BuildContext context) {
    if (total <= 1) return const SizedBox.shrink();
    return Column(
      children: [
        Text(
          '$label $current of $total',
          style: BlushTheme.body(16, weight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= total; i++) ...[
              if (i > 1) const SizedBox(width: 8),
              _pip(
                done: completed.contains(i) ||
                    (assumePreviousDone && i < current),
                active: i == current && !completed.contains(i),
                index: i,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _pip({
    required bool done,
    required bool active,
    required int index,
  }) {
    final bg = done
        ? const Color(0xFF3D9A6A)
        : active
            ? BlushTheme.roseDeep
            : BlushTheme.creamDark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: done || active ? 36 : 28,
      height: done || active ? 36 : 28,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(
        child: done
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : Text(
                '$index',
                style: BlushTheme.body(
                  13,
                  weight: FontWeight.w700,
                  color: active ? Colors.white : BlushTheme.inkMuted,
                ),
              ),
      ),
    );
  }
}

/// Side-by-side chrome | media on short/wide viewports; stacked otherwise.
class PairingAdaptiveBody extends StatelessWidget {
  const PairingAdaptiveBody({
    super.key,
    required this.chrome,
    required this.media,
    this.below,
  });

  final Widget chrome;
  final Widget media;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final win = BlushWindowSize.of(context);
    final mediaColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        media,
        if (below != null) ...[
          const SizedBox(height: 16),
          below!,
        ],
      ],
    );

    if (win.preferSplit) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: chrome),
          const SizedBox(width: 20),
          Expanded(flex: 4, child: mediaColumn),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        chrome,
        const SizedBox(height: 16),
        mediaColumn,
      ],
    );
  }
}

class QrCodeCard extends StatelessWidget {
  const QrCodeCard({
    super.key,
    required this.data,
    this.confirmed = false,
    this.size,
  });

  final String data;
  final bool confirmed;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final qrSize = size ?? PairingMediaMetrics.of(context).qrSize;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: confirmed
                  ? const Color(0xFF3D9A6A)
                  : Colors.white,
              width: 3,
            ),
          ),
          child: QrImageView(
            data: data,
            size: qrSize,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        if (confirmed) const _GreenCheckBurst(),
      ],
    );
  }
}

class _GreenCheckBurst extends StatelessWidget {
  const _GreenCheckBurst();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: const Color(0xFF3D9A6A).withValues(alpha: 0.94),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3D9A6A).withValues(alpha: 0.35),
            blurRadius: 16,
          ),
        ],
      ),
      child: const Icon(Icons.check, color: Colors.white, size: 52),
    );
  }
}

class BigNextButton extends StatelessWidget {
  const BigNextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

class PairingScannerPane extends StatelessWidget {
  const PairingScannerPane({
    super.key,
    required this.controller,
    required this.onDetect,
    this.flashCheck = false,
    this.height,
  });

  final MobileScannerController controller;
  final void Function(String value) onDetect;
  final bool flashCheck;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final h = height ?? PairingMediaMetrics.of(context).scannerHeight;
    final frame = (h * 0.7).clamp(120.0, 200.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              onDetect: (capture) {
                final barcodes = capture.barcodes;
                if (barcodes.isEmpty) return;
                final v = barcodes.first.rawValue;
                if (v != null) onDetect(v);
              },
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: frame,
                  height: frame,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: flashCheck
                          ? const Color(0xFF3D9A6A)
                          : Colors.white,
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
            if (flashCheck) const Center(child: _GreenCheckBurst()),
          ],
        ),
      ),
    );
  }
}
