import 'package:flutter/foundation.dart';

/// Tagged logs for validating LAN / Online / navigation on device (logcat).
///
/// Filter either device:
/// `adb logcat -s flutter | grep '\[Blush/'`
/// or broader:
/// `adb logcat | grep '\[Blush/'`
void blushLog(String tag, String message) {
  final line = '[Blush/$tag] $message';
  // print survives release builds where debugPrint may be throttled/harder to spot.
  // ignore: avoid_print
  print(line);
  debugPrint(line);
}
