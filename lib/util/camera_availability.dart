import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'blush_log.dart';

const _deviceChannel = MethodChannel('com.blushcraft.blushcraft/device');

/// Whether this device exposes at least one camera (Camera2 id list).
///
/// Do **not** use `availableCameras()` / CameraX here: on BlissOS tablets with
/// 0 cameras, CameraX retries then kills the process with an uncaught exception.
Future<bool> deviceHasUsableCamera() async {
  if (_cached != null) return _cached!;
  if (kIsWeb) {
    _cached = false;
    return false;
  }
  try {
    final ok = await _deviceChannel.invokeMethod<bool>('hasCamera');
    _cached = ok == true;
    blushLog('AV', 'usableCameras(camera2)=$_cached');
  } catch (e) {
    blushLog('AV', 'usableCameras probe failed: $e');
    _cached = false;
  }
  return _cached!;
}

bool? _cached;
