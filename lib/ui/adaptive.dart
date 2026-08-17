import 'package:flutter/material.dart';

/// Material / Android window width classes (available width in dp).
///
/// See https://developer.android.com/develop/ui/views/layout/responsive-adaptive-design-with-views
enum BlushWidthClass {
  /// Available width under 600 — phones in portrait, narrow multi-window.
  compact,

  /// 600–839 — large phones landscape, small tablets.
  medium,

  /// ≥ 840 — tablets, unfolded foldables, desktops.
  expanded,
}

/// Material / Android window height classes (available height in dp).
enum BlushHeightClass {
  /// Available height &lt; 480 — typical phone landscape.
  compact,

  /// 480–899.
  medium,

  /// ≥ 900.
  expanded,
}

/// Snapshot of the app window’s size classes (multi-window safe).
class BlushWindowSize {
  const BlushWindowSize({
    required this.size,
    required this.widthClass,
    required this.heightClass,
  });

  final Size size;
  final BlushWidthClass widthClass;
  final BlushHeightClass heightClass;

  bool get widthCompact => widthClass == BlushWidthClass.compact;
  bool get widthMedium => widthClass == BlushWidthClass.medium;
  bool get widthExpanded => widthClass == BlushWidthClass.expanded;
  bool get widthMediumOrUp => widthClass != BlushWidthClass.compact;

  bool get heightCompact => heightClass == BlushHeightClass.compact;

  /// Prefer side-by-side panes: medium+ width **or** short (landscape) height.
  bool get preferSplit => widthMediumOrUp || heightCompact;

  /// Horizontal page padding derived from width class.
  double get pagePadding => switch (widthClass) {
        BlushWidthClass.compact => 24,
        BlushWidthClass.medium => 40,
        BlushWidthClass.expanded => 64,
      };

  /// Max content width for text-heavy screens on large windows.
  static const double contentMaxWidth = 720;

  factory BlushWindowSize.fromSize(Size size) {
    return BlushWindowSize(
      size: size,
      widthClass: widthClassFor(size.width),
      heightClass: heightClassFor(size.height),
    );
  }

  factory BlushWindowSize.of(BuildContext context) {
    return BlushWindowSize.fromSize(MediaQuery.sizeOf(context));
  }

  static BlushWidthClass widthClassFor(double width) {
    if (width < 600) return BlushWidthClass.compact;
    if (width < 840) return BlushWidthClass.medium;
    return BlushWidthClass.expanded;
  }

  static BlushHeightClass heightClassFor(double height) {
    if (height < 480) return BlushHeightClass.compact;
    if (height < 900) return BlushHeightClass.medium;
    return BlushHeightClass.expanded;
  }
}

/// Centers [child] with a readable max width on expanded windows.
class BlushContentWidth extends StatelessWidget {
  const BlushContentWidth({
    super.key,
    required this.child,
    this.maxWidth = BlushWindowSize.contentMaxWidth,
    this.force = false,
  });

  final Widget child;
  final double maxWidth;

  /// When true, always apply [maxWidth] (not only on expanded).
  final bool force;

  @override
  Widget build(BuildContext context) {
    final win = BlushWindowSize.of(context);
    if (!force && !win.widthExpanded) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Stacks [start]/[end] on compact portrait; side-by-side when [preferSplit].
class AdaptiveSplit extends StatelessWidget {
  const AdaptiveSplit({
    super.key,
    required this.start,
    required this.end,
    this.startFlex = 1,
    this.endFlex = 1,
    this.gap = 24,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.scrollWhenStacked = true,
    this.preferSplitOverride,
  });

  final Widget start;
  final Widget end;
  final int startFlex;
  final int endFlex;
  final double gap;
  final CrossAxisAlignment crossAxisAlignment;
  final bool scrollWhenStacked;

  /// When non-null, overrides [BlushWindowSize.preferSplit].
  final bool? preferSplitOverride;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final win = BlushWindowSize.fromSize(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final split = preferSplitOverride ?? win.preferSplit;
        if (split && constraints.maxWidth >= 480) {
          return Row(
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Expanded(flex: startFlex, child: start),
              SizedBox(width: gap),
              Expanded(flex: endFlex, child: end),
            ],
          );
        }

        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            start,
            SizedBox(height: gap),
            end,
          ],
        );

        if (!scrollWhenStacked) return column;

        final maxH = constraints.maxHeight;
        if (!maxH.isFinite || maxH <= 0) {
          return SingleChildScrollView(child: column);
        }
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: maxH),
            child: column,
          ),
        );
      },
    );
  }
}

/// Scrollable body that fills remaining height when content is shorter.
class AdaptiveScrollBody extends StatelessWidget {
  const AdaptiveScrollBody({
    super.key,
    required this.child,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: maxH.isFinite ? maxH : 0,
            ),
            child: Align(alignment: alignment, child: child),
          ),
        );
      },
    );
  }
}

/// Metrics for choice hand cards based on available height.
class HandStripMetrics {
  const HandStripMetrics({
    required this.stripHeight,
    required this.cardWidth,
  });

  final double stripHeight;
  final double cardWidth;

  factory HandStripMetrics.forWindow(BlushWindowSize win) {
    if (win.heightCompact) {
      return const HandStripMetrics(stripHeight: 110, cardWidth: 130);
    }
    if (win.widthCompact) {
      return const HandStripMetrics(stripHeight: 150, cardWidth: 160);
    }
    return const HandStripMetrics(stripHeight: 160, cardWidth: 168);
  }

  factory HandStripMetrics.of(BuildContext context) {
    return HandStripMetrics.forWindow(BlushWindowSize.of(context));
  }
}

/// Pairing QR / scanner size from available space.
class PairingMediaMetrics {
  const PairingMediaMetrics({
    required this.qrSize,
    required this.scannerHeight,
  });

  final double qrSize;
  final double scannerHeight;

  factory PairingMediaMetrics.forConstraints(BoxConstraints constraints) {
    final win = BlushWindowSize.fromSize(
      Size(constraints.maxWidth, constraints.maxHeight),
    );
    final short = win.heightCompact;
    final side = short || win.widthMediumOrUp;
    // When split, media sits in roughly half the width.
    final widthBudget = side
        ? (constraints.maxWidth - 24) * 0.48
        : constraints.maxWidth - 48;
    final heightBudget = short
        ? constraints.maxHeight * 0.72
        : constraints.maxHeight * 0.45;
    final qr = widthBudget
        .clamp(160.0, short ? 200.0 : 260.0)
        .clamp(160.0, heightBudget.isFinite ? heightBudget : 260.0);
    final scanH = (short
            ? (heightBudget.isFinite ? heightBudget : 200.0)
            : 280.0)
        .clamp(160.0, 280.0);
    return PairingMediaMetrics(
      qrSize: qr.toDouble(),
      scannerHeight: scanH.toDouble(),
    );
  }

  factory PairingMediaMetrics.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final availableH = size.height - pad.vertical - kToolbarHeight - 32;
    return PairingMediaMetrics.forConstraints(
      BoxConstraints(maxWidth: size.width, maxHeight: availableH),
    );
  }
}
