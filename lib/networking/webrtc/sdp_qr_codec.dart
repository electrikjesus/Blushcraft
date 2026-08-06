import 'dart:convert';
import 'dart:io';

/// Compress / encode WebRTC signaling blobs for QR or paste.
class SdpQrCodec {
  static const packageId = 'com.blushcraft.blushcraft';

  /// Target size for a single scannable QR (data-channel invites are usually under this).
  static const maxSingleQrChars = 900;

  static String encodeEnvelope({
    required String role,
    required String sessionId,
    required String displayName,
    required String sdp,
    required List<String> ice,
  }) {
    final map = <String, dynamic>{
      'v': 1,
      'role': role,
      'session': sessionId,
      'name': displayName,
      'sdp': sdp,
      'ice': ice,
      'pkg': packageId,
    };
    final jsonBytes = utf8.encode(jsonEncode(map));
    final compressed = gzip.encode(jsonBytes);
    final b64 = base64Url.encode(compressed).replaceAll('=', '');
    return 'BC1:$b64';
  }

  /// Accept a single `BC1:` blob or pasted multi-part `BC1C:` chunks.
  static String normalizeIncoming(String raw) {
    final text = raw.trim();
    // Payload may itself start with "BC1:", so allow ':' inside the slice.
    final chunkRe = RegExp(r'BC1C:\d+/\d+:\S+');
    final chunks = chunkRe.allMatches(text).map((m) => m.group(0)!).toList();
    if (chunks.isNotEmpty) {
      return joinChunks(chunks);
    }
    return text;
  }

  static Map<String, dynamic> decodeEnvelope(String raw) {
    var text = normalizeIncoming(raw);
    final marker = text.indexOf('BC1:');
    if (marker >= 0) {
      text = text.substring(marker);
    }
    if (text.startsWith('BC1C:')) {
      throw const FormatException('Pass joined chunks via joinChunks first');
    }
    if (!text.startsWith('BC1:')) {
      throw const FormatException(
        'Not a Blushcraft invite (missing BC1: prefix)',
      );
    }
    final b64 = _padBase64(text.substring(4));
    final compressed = base64Url.decode(b64);
    final jsonBytes = gzip.decode(compressed);
    final map = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
    if (map['v'] != 1) {
      throw FormatException('Unsupported invite version: ${map['v']}');
    }
    if (map['pkg'] != null && map['pkg'] != packageId) {
      throw const FormatException('Invite is for a different app package');
    }
    return map;
  }

  static String _padBase64(String s) {
    final mod = s.length % 4;
    if (mod == 0) return s;
    return s.padRight(s.length + (4 - mod), '=');
  }

  /// Split a long payload into numbered chunks for multi-QR (rare).
  static List<String> chunk(String payload, {int size = maxSingleQrChars}) {
    if (payload.length <= size) return [payload];
    final parts = <String>[];
    final total = (payload.length / size).ceil();
    for (var i = 0; i < total; i++) {
      final start = i * size;
      final end =
          (start + size < payload.length) ? start + size : payload.length;
      parts.add('BC1C:${i + 1}/$total:${payload.substring(start, end)}');
    }
    return parts;
  }

  /// Reassemble [chunk] parts or return a single BC1 payload as-is.
  static String joinChunks(List<String> parts) {
    if (parts.length == 1 && parts.first.trim().startsWith('BC1:')) {
      return parts.first.trim();
    }
    final re = RegExp(r'^BC1C:(\d+)/(\d+):(.*)$');
    final sorted = <int, String>{};
    var total = 0;
    for (final p in parts) {
      final m = re.firstMatch(p.trim());
      if (m == null) {
        throw const FormatException('Invalid chunk');
      }
      total = int.parse(m.group(2)!);
      sorted[int.parse(m.group(1)!)] = m.group(3)!;
    }
    if (sorted.length != total) {
      throw FormatException('Missing chunks: have ${sorted.length} of $total');
    }
    final buf = StringBuffer();
    for (var i = 1; i <= total; i++) {
      buf.write(sorted[i]);
    }
    return buf.toString();
  }
}
