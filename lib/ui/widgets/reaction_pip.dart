import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../camera/reaction_camera.dart';
import '../theme.dart';

/// Compact peer + self camera overlay that stays clear of game content.
class ReactionPip extends StatelessWidget {
  const ReactionPip({
    super.key,
    required this.av,
    this.peerJpeg,
    required this.onToggleCamera,
    required this.onToggleMic,
    this.alignment = Alignment.topRight,
  });

  final ReactionAvController av;
  final Uint8List? peerJpeg;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleMic;
  final Alignment alignment;

  static const double width = 132;
  static const double peerHeight = 168;
  static const double selfSize = 56;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _peerTile(),
                  Positioned(
                    right: 6,
                    bottom: -selfSize * 0.35,
                    child: _selfTile(),
                  ),
                ],
              ),
              const SizedBox(height: selfSize * 0.4 + 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _chip(
                    icon: av.cameraEnabled ? Icons.videocam : Icons.videocam_off,
                    on: av.cameraEnabled,
                    onTap: onToggleCamera,
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    icon: av.micEnabled ? Icons.mic : Icons.mic_off,
                    on: av.micEnabled,
                    onTap: onToggleMic,
                  ),
                  if (!av.peerMicEnabled) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.mic_off, size: 16, color: BlushTheme.roseDeep),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _peerTile() {
    Widget child;
    if (peerJpeg != null && av.peerCameraEnabled) {
      child = Image.memory(peerJpeg!, fit: BoxFit.cover);
    } else if (!av.peerCameraEnabled) {
      child = _placeholder('Partner\ncamera off');
    } else {
      child = _placeholder(av.ready ? 'Waiting for\npartner…' : 'Connecting…');
    }

    return Container(
      width: width,
      height: peerHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
        boxShadow: [
          BoxShadow(
            color: BlushTheme.charcoal.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _selfTile() {
    Widget child;
    if (av.showPreview && av.controller != null) {
      child = CameraPreview(av.controller!);
    } else {
      child = _placeholder(
        av.cameraEnabled ? 'You' : 'Cam off',
        compact: true,
      );
    }

    return Container(
      width: selfSize,
      height: selfSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: BlushTheme.charcoal.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _placeholder(String text, {bool compact = false}) {
    return ColoredBox(
      color: BlushTheme.creamDark,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: BlushTheme.body(
            compact ? 9 : 11,
            color: BlushTheme.inkMuted,
          ),
        ),
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required bool on,
    required VoidCallback onTap,
  }) {
    return Material(
      color: on
          ? BlushTheme.charcoal.withValues(alpha: 0.55)
          : BlushTheme.roseDeep.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}
