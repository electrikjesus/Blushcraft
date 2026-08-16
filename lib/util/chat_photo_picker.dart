import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../state/chat_controller.dart';

/// Pick and compress a JPEG for [ChatPhotoMessage] (≤ [ChatController.maxBase64Chars]).
class ChatPhotoPicker {
  ChatPhotoPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<({String base64, String mime})?> pickGallery() =>
      _pick(ImageSource.gallery);

  Future<({String base64, String mime})?> pickCamera() =>
      _pick(ImageSource.camera);

  Future<({String base64, String mime})?> _pick(ImageSource source) async {
    // First pass: aggressive resize for wire size.
    var file = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 70,
    );
    if (file == null) return null;
    var bytes = await file.readAsBytes();
    var b64 = base64Encode(bytes);
    if (b64.length <= ChatController.maxBase64Chars) {
      return (base64: b64, mime: 'image/jpeg');
    }

    // Retry smaller.
    file = await _picker.pickImage(
      source: source,
      maxWidth: 960,
      maxHeight: 960,
      imageQuality: 55,
    );
    if (file == null) return null;
    bytes = await file.readAsBytes();
    b64 = base64Encode(bytes);
    if (b64.length <= ChatController.maxBase64Chars) {
      return (base64: b64, mime: 'image/jpeg');
    }

    // Last resort: 640 @ 40.
    file = await _picker.pickImage(
      source: source,
      maxWidth: 640,
      maxHeight: 640,
      imageQuality: 40,
    );
    if (file == null) return null;
    bytes = await file.readAsBytes();
    b64 = base64Encode(bytes);
    if (b64.length > ChatController.maxBase64Chars) {
      debugPrint('chat photo still too large: ${b64.length}');
      return null;
    }
    return (base64: b64, mime: 'image/jpeg');
  }

  /// Shrink an existing base64 JPEG (e.g. reaction selfie) under the wire cap.
  static Future<String?> shrinkBase64Jpeg(String base64Jpeg) async {
    if (base64Jpeg.length <= ChatController.maxBase64Chars) return base64Jpeg;
    try {
      final raw = base64Decode(base64Jpeg);
      // Re-encode via picker isn't available; drop if oversize selfie.
      // Reaction captures are usually small; if not, refuse send.
      if (raw.length > ChatController.maxBase64Chars) return null;
      final again = base64Encode(raw);
      return again.length <= ChatController.maxBase64Chars ? again : null;
    } catch (_) {
      return null;
    }
  }

  static Uint8List? decodeJpeg(String base64Jpeg) {
    try {
      return base64Decode(base64Jpeg);
    } catch (_) {
      return null;
    }
  }
}
