import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../camera/reaction_camera.dart';
import '../theme.dart';

/// How reaction cameras sit relative to game content.
enum ReactionAvLayout {
  /// Peer tile beside content (better on tablets / landscape).
  side,

  /// Compact peer + self row above content (better on phones).
  strip,
}

/// User preference; [auto] picks strip under 600px width, side otherwise.
enum ReactionAvLayoutPref {
  auto,
  strip,
  side;

  String get storageValue => name;

  static ReactionAvLayoutPref fromStorage(String? raw) {
    return ReactionAvLayoutPref.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => ReactionAvLayoutPref.auto,
    );
  }

  ReactionAvLayout resolve({required double width}) {
    switch (this) {
      case ReactionAvLayoutPref.strip:
        return ReactionAvLayout.strip;
      case ReactionAvLayoutPref.side:
        return ReactionAvLayout.side;
      case ReactionAvLayoutPref.auto:
        return width < 600 ? ReactionAvLayout.strip : ReactionAvLayout.side;
    }
  }

  String get label {
    switch (this) {
      case ReactionAvLayoutPref.auto:
        return 'Auto layout';
      case ReactionAvLayoutPref.strip:
        return 'Camera row';
      case ReactionAvLayoutPref.side:
        return 'Side panel';
    }
  }

  IconData get icon {
    switch (this) {
      case ReactionAvLayoutPref.auto:
        return Icons.stay_current_portrait;
      case ReactionAvLayoutPref.strip:
        return Icons.view_agenda_outlined;
      case ReactionAvLayoutPref.side:
        return Icons.vertical_split_outlined;
    }
  }

  ReactionAvLayoutPref get next {
    final i = index;
    return ReactionAvLayoutPref.values[(i + 1) % ReactionAvLayoutPref.values.length];
  }
}

/// Content-sized media metrics derived from available width.
class ReactionAvMetrics {
  const ReactionAvMetrics({
    required this.stripHeight,
    required this.audioHeight,
    required this.selfSize,
    required this.sideWidth,
    required this.sidePeerHeight,
    required this.compact,
  });

  final double stripHeight;
  final double audioHeight;
  final double selfSize;
  final double sideWidth;
  final double sidePeerHeight;
  final bool compact;

  /// Scale tiles to the play area width — never grow to fill leftover height.
  factory ReactionAvMetrics.forWidth(double width) {
    final compact = width < 420;
    final stripHeight = (width * 0.14).clamp(56.0, 88.0);
    final audioHeight = compact ? 56.0 : 60.0;
    final selfSize = (stripHeight * 0.55).clamp(32.0, 44.0);
    final sideWidth = (width * 0.16).clamp(96.0, 120.0);
    final sidePeerHeight = sideWidth * 1.15;
    return ReactionAvMetrics(
      stripHeight: stripHeight,
      audioHeight: audioHeight,
      selfSize: selfSize,
      sideWidth: sideWidth,
      sidePeerHeight: sidePeerHeight,
      compact: compact,
    );
  }

  double sideReserveWidth(ReactionAvLayout layout) =>
      layout == ReactionAvLayout.side ? sideWidth + 12 : 0;
}

/// Peer + self cameras (or audio-only tiles) with mic/camera toggles.
///
/// Sizes itself to content based on [metrics] / available width — callers
/// should not force a large fraction of the play area.
class ReactionAvPanel extends StatelessWidget {
  const ReactionAvPanel({
    super.key,
    required this.av,
    required this.layout,
    required this.layoutPref,
    required this.metrics,
    this.peerJpeg,
    this.peerVideo,
    this.localVideo,
    required this.onToggleCamera,
    required this.onToggleMic,
    required this.onCycleLayout,
  });

  final ReactionAvController av;
  final ReactionAvLayout layout;
  final ReactionAvLayoutPref layoutPref;
  final ReactionAvMetrics metrics;
  final Uint8List? peerJpeg;
  final Widget? peerVideo;
  final Widget? localVideo;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleMic;
  final VoidCallback onCycleLayout;

  /// @deprecated Prefer [ReactionAvMetrics]; kept for call-site migration.
  static const double stripHeight = 72;
  static const double audioStripHeight = 48;

  static double sideReserveWidth(ReactionAvLayout layout, [double width = 400]) =>
      ReactionAvMetrics.forWidth(width).sideReserveWidth(layout);

  @override
  Widget build(BuildContext context) {
    if (av.audioOnlyLiveMedia) {
      return _audioOnlyStrip();
    }
    return layout == ReactionAvLayout.strip ? _strip() : _side();
  }

  Widget _audioOnlyStrip() {
    final h = metrics.audioHeight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 10, 6),
      child: SizedBox(
        height: h,
        child: Row(
          children: [
            Expanded(child: _audioChip(isPeer: true)),
            const SizedBox(width: 8),
            Expanded(child: _audioChip(isPeer: false)),
            const SizedBox(width: 6),
            _controls(vertical: false, cameraAllowed: false),
          ],
        ),
      ),
    );
  }

  Widget _audioChip({required bool isPeer}) {
    final micOn = isPeer ? av.peerMicEnabled : av.micEnabled;
    final label = isPeer ? 'Partner' : 'You';
    final bands =
        isPeer ? av.peerDisplaySpectrum : av.localDisplaySpectrum;

    return Container(
      decoration: BoxDecoration(
        color: BlushTheme.creamDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: micOn
              ? BlushTheme.roseDeep.withValues(alpha: 0.5)
              : BlushTheme.creamDark,
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      child: Row(
        children: [
          Icon(
            micOn ? Icons.graphic_eq : Icons.mic_off,
            size: 16,
            color: micOn ? BlushTheme.roseDeep : BlushTheme.inkMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  micOn ? label : '$label · muted',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BlushTheme.body(11, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 22,
                  child: _AudioVisualizer(
                    bands: bands,
                    active: micOn,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _strip() {
    final h = metrics.stripHeight;
    final self = metrics.selfSize;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: h,
            child: Stack(
              children: [
                Positioned.fill(child: _peerFrame(borderRadius: 12)),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _chip(
                    icon: layoutPref.icon,
                    on: true,
                    onTap: onCycleLayout,
                    tooltip: '${layoutPref.label} (tap to change)',
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _selfTile(size: self),
        const SizedBox(width: 6),
        _controls(vertical: true, cameraAllowed: av.deviceHasCamera),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 10, 6),
      child: SizedBox(height: h, child: row),
    );
  }

  Widget _side() {
    final w = metrics.sideWidth;
    final peerH = metrics.sidePeerHeight;
    final self = metrics.selfSize;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 10, 6),
      child: SizedBox(
        width: w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: w,
                  height: peerH,
                  child: _peerFrame(borderRadius: 12),
                ),
                Positioned(
                  right: 4,
                  bottom: -self * 0.3,
                  child: _selfTile(size: self),
                ),
              ],
            ),
            SizedBox(height: self * 0.35 + 6),
            _controls(vertical: false, cameraAllowed: av.deviceHasCamera),
          ],
        ),
      ),
    );
  }

  Widget _peerFrame({required double borderRadius}) {
    Widget child;
    if (!av.peerHasCamera) {
      child = _placeholder(
        av.peerMicEnabled ? 'Audio only' : 'Mic off',
      );
    } else if (peerVideo != null && av.peerCameraEnabled) {
      child = peerVideo!;
    } else if (peerJpeg != null && av.peerCameraEnabled) {
      child = Image.memory(
        peerJpeg!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    } else if (!av.peerCameraEnabled) {
      child = _placeholder(
        av.peerMicEnabled ? 'Cam off' : 'Waiting…',
      );
    } else {
      child = _placeholder(
        av.ready || peerVideo != null ? '…' : '…',
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: BlushTheme.charcoal.withValues(alpha: 0.14),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _selfTile({required double size}) {
    Widget child;
    if (!av.deviceHasCamera) {
      child = _placeholder(
        av.micEnabled ? 'You' : 'Off',
        compact: true,
      );
    } else if (localVideo != null && av.cameraEnabled) {
      child = localVideo!;
    } else if (av.showPreview && av.controller != null) {
      child = CameraPreview(av.controller!);
    } else {
      child = _placeholder(
        av.cameraEnabled ? 'You' : 'Off',
        compact: true,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: BlushTheme.charcoal.withValues(alpha: 0.18),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _controls({
    required bool vertical,
    required bool cameraAllowed,
  }) {
    final chips = <Widget>[
      if (cameraAllowed)
        _chip(
          icon: av.cameraEnabled ? Icons.videocam : Icons.videocam_off,
          on: av.cameraEnabled,
          onTap: onToggleCamera,
          tooltip: av.cameraEnabled ? 'Camera on' : 'Camera off',
          compact: true,
        ),
      _micChip(compact: true),
    ];

    if (!vertical && !av.audioOnlyLiveMedia) {
      chips.add(
        _chip(
          icon: layoutPref.icon,
          on: true,
          onTap: onCycleLayout,
          tooltip: '${layoutPref.label} (tap to change)',
          compact: true,
        ),
      );
    }

    if (!av.peerMicEnabled) {
      chips.add(Icon(Icons.mic_off, size: 14, color: BlushTheme.roseDeep));
    }

    if (vertical) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(height: 3),
            chips[i],
          ],
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          chips[i],
        ],
      ],
    );
  }

  Widget _placeholder(String text, {bool compact = false}) {
    return ColoredBox(
      color: BlushTheme.creamDark,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: BlushTheme.body(
              compact ? 8 : 10,
              color: BlushTheme.inkMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _micChip({required bool compact}) {
    final pad = compact ? 5.0 : 7.0;
    final size = compact ? 13.0 : 15.0;
    final chip = Material(
      color: av.micEnabled
          ? BlushTheme.charcoal.withValues(alpha: 0.55)
          : BlushTheme.roseDeep.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onToggleMic,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, compact ? 3 : 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                av.micEnabled ? Icons.mic : Icons.mic_off,
                color: Colors.white,
                size: size,
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: 24,
                height: 14,
                child: _AudioVisualizer(
                  bands: av.localDisplaySpectrum,
                  active: av.micEnabled,
                  onDark: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Tooltip(
      message: av.micEnabled ? 'Mic on' : 'Mic off',
      child: chip,
    );
  }

  Widget _chip({
    required IconData icon,
    required bool on,
    required VoidCallback onTap,
    String? tooltip,
    bool compact = false,
  }) {
    final pad = compact ? 5.0 : 7.0;
    final size = compact ? 13.0 : 15.0;
    final chip = Material(
      color: on
          ? BlushTheme.charcoal.withValues(alpha: 0.55)
          : BlushTheme.roseDeep.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip, child: chip);
  }
}

/// Decorative bouncing bars — not a volume / EQ meter.
class _AudioVisualizer extends StatelessWidget {
  const _AudioVisualizer({
    required this.bands,
    required this.active,
    this.onDark = false,
  });

  final List<double> bands;
  final bool active;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final bar = onDark ? Colors.white : BlushTheme.roseDeep;
    final idle = onDark
        ? Colors.white.withValues(alpha: 0.22)
        : BlushTheme.charcoal.withValues(alpha: 0.12);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < bands.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: _VisualizerBar(
              value: active ? bands[i].clamp(0.0, 1.0) : 0,
              color: bar,
              idleColor: idle,
            ),
          ),
        ],
      ],
    );
  }
}

class _VisualizerBar extends StatelessWidget {
  const _VisualizerBar({
    required this.value,
    required this.color,
    required this.idleColor,
  });

  final double value;
  final Color color;
  final Color idleColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final minH = (maxH * 0.18).clamp(2.0, 4.0);
        final h = minH + (maxH - minH) * value;
        return Align(
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 70),
            curve: Curves.easeOut,
            height: h,
            decoration: BoxDecoration(
              color: value > 0.04 ? color : idleColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        );
      },
    );
  }
}
