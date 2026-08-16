import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

const avConsentPrefKey = 'blushcraft_av_consent';
const avWantCameraPrefKey = 'blushcraft_want_camera';
const avWantMicPrefKey = 'blushcraft_want_mic';
const avWantLiveViewPrefKey = 'blushcraft_want_live_view';

Future<bool> loadAvConsentGiven() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(avConsentPrefKey) ?? false;
}

Future<void> saveAvConsentGiven() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(avConsentPrefKey, true);
}

Future<({bool camera, bool mic, bool liveView})> loadAvWantFlags() async {
  final prefs = await SharedPreferences.getInstance();
  return (
    camera: prefs.getBool(avWantCameraPrefKey) ?? false,
    mic: prefs.getBool(avWantMicPrefKey) ?? false,
    liveView: prefs.getBool(avWantLiveViewPrefKey) ?? false,
  );
}

Future<void> saveAvWantFlags({
  required bool camera,
  required bool mic,
  required bool liveView,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(avWantCameraPrefKey, camera);
  await prefs.setBool(avWantMicPrefKey, mic);
  await prefs.setBool(avWantLiveViewPrefKey, liveView);
}

/// Returns true if the user agrees to share reaction camera/mic.
Future<bool> showAvConsentSheet(BuildContext context) async {
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Share reaction media?', style: BlushTheme.display(22)),
            const SizedBox(height: 12),
            Text(
              'Mic and camera are optional. If you allow them, your partner '
              'can hear and (when a camera is available) see you during the '
              'round. Live media needs both of you to opt in; if either '
              'device has no camera, it stays audio-only. You can turn mic or '
              'camera off anytime.',
              style: BlushTheme.body(15),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
          ],
        ),
      );
    },
  );
  if (agreed == true) {
    await saveAvConsentGiven();
    return true;
  }
  return false;
}
