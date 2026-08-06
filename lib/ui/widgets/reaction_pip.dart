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

/// Peer + self cameras with mic/camera toggles.
///
/// [ReactionAvLayout.strip] is a horizontal bar for phones; with [expand] it
/// fills leftover vertical space so game controls can sit at the bottom.
/// [ReactionAvLayout.side] is the classic top-right PiP for wider screens.
class ReactionAvPanel extends StatelessWidget {
  const ReactionAvPanel({
    super.key,
    required this.av,
    required this.layout,
    required this.layoutPref,
    this.peerJpeg,
    this.peerVideo,
    this.localVideo,
    required this.onToggleCamera,
    required this.onToggleMic,
    required this.onCycleLayout,
    this.expand = false,
  });

  final ReactionAvController av;
  final ReactionAvLayout layout;
  final ReactionAvLayoutPref layoutPref;
  final Uint8List? peerJpeg;
  final Widget? peerVideo;
  final Widget? localVideo;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleMic;
  final VoidCallback onCycleLayout;

  /// When true (strip only), fill the parent instead of a fixed short bar.
  final bool expand;

  static const double sideWidth = 132;
  static const double sidePeerHeight = 168;
  static const double stripHeight = 88;
  static const double selfSize = 48;
  static const double selfSizeExpanded = 64;

  /// Space reserved when overlaying a side panel on narrow content.
  static double sideReserveWidth(ReactionAvLayout layout) =>
      layout == ReactionAvLayout.side ? sideWidth + 16 : 0;

  @override
  Widget build(BuildContext context) {
    return layout == ReactionAvLayout.strip ? _strip() : _side();
  }

  Widget _strip() {
    final self = expand ? selfSizeExpanded : selfSize;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _peerFrame(borderRadius: expand ? 18 : 14)),
              Positioned(
                top: 6,
                right: 6,
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
        const SizedBox(width: 10),
        Center(child: _selfTile(size: self)),
        const SizedBox(width: 8),
        _controls(vertical: true),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 12, expand ? 12 : 8),
      child: expand
          ? row
          : SizedBox(height: stripHeight, child: row),
    );
  }

  Widget _side() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
      child: SizedBox(
        width: sideWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: sideWidth,
                  height: sidePeerHeight,
                  child: _peerFrame(borderRadius: 14),
                ),
                Positioned(
                  right: 6,
                  bottom: -selfSize * 0.35,
                  child: _selfTile(size: selfSize),
                ),
              ],
            ),
            const SizedBox(height: selfSize * 0.4 + 8),
            _controls(vertical: false),
          ],
        ),
      ),
    );
  }

  Widget _peerFrame({required double borderRadius}) {
    Widget child;
    if (peerVideo != null && av.peerCameraEnabled) {
      child = peerVideo!;
    } else if (peerJpeg != null && av.peerCameraEnabled) {
      child = Image.memory(peerJpeg!, fit: BoxFit.cover);
    } else if (!av.peerCameraEnabled) {
      child = _placeholder('Waiting for partner share');
    } else {
      child = _placeholder(
        av.ready || peerVideo != null ? 'Waiting for partner…' : 'Connecting…',
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
        boxShadow: [
          BoxShadow(
            color: BlushTheme.charcoal.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _selfTile({double size = selfSize}) {
    Widget child;
    if (localVideo != null && av.cameraEnabled) {
      child = localVideo!;
    } else if (av.showPreview && av.controller != null) {
      child = CameraPreview(av.controller!);
    } else {
      child = _placeholder(
        av.cameraEnabled ? 'You' : 'Cam off',
        compact: true,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: BlushTheme.charcoal.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _controls({required bool vertical}) {
    final chips = <Widget>[
      _chip(
        icon: av.cameraEnabled ? Icons.videocam : Icons.videocam_off,
        on: av.cameraEnabled,
        onTap: onToggleCamera,
        tooltip: av.cameraEnabled ? 'Camera on' : 'Camera off',
        compact: vertical,
      ),
      _chip(
        icon: av.micEnabled ? Icons.mic : Icons.mic_off,
        on: av.micEnabled,
        onTap: onToggleMic,
        tooltip: av.micEnabled ? 'Mic on' : 'Mic off',
        compact: vertical,
      ),
    ];

    if (!vertical) {
      chips.add(
        _chip(
          icon: layoutPref.icon,
          on: true,
          onTap: onCycleLayout,
          tooltip: '${layoutPref.label} (tap to change)',
        ),
      );
    }

    if (!av.peerMicEnabled) {
      chips.add(Icon(Icons.mic_off, size: 16, color: BlushTheme.roseDeep));
    }

    if (vertical) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            chips[i],
          ],
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
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
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: BlushTheme.body(
              compact ? 9 : 11,
              color: BlushTheme.inkMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required bool on,
    required VoidCallback onTap,
    String? tooltip,
    bool compact = false,
  }) {
    final pad = compact ? 6.0 : 8.0;
    final size = compact ? 14.0 : 16.0;
    final chip = Material(
      color: on
          ? BlushTheme.charcoal.withValues(alpha: 0.55)
          : BlushTheme.roseDeep.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
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