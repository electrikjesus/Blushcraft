import 'dart:convert';
import 'dart:io';

import '../../util/blush_log.dart';

/// Compress / encode WebRTC signaling blobs for QR or paste.
class SdpQrCodec {
  static const packageId = 'com.blushcraft.blushcraft';

  /// Target payload per on-screen QR.
  ///
  /// Keep this well under a dense Version-20 code so phone cameras can lock
  /// quickly. Clipboard / Share still send the full `BC1:` blob.
  static const maxSingleQrChars = 420;

  static String encodeEnvelope({
    required String role,
    required String sessionId,
    required String displayName,
    required String sdp,
    required List<String> ice,
  }) {
    // Keep the envelope lean: omit pkg (checked only when present).
    final map = <String, dynamic>{
      'v': 1,
      'role': role,
      'session': sessionId,
      'name': displayName,
      'sdp': sdp,
      'ice': ice,
    };
    final jsonBytes = utf8.encode(jsonEncode(map));
    final compressed = gzip.encode(jsonBytes);
    final b64 = base64Url.encode(compressed).replaceAll('=', '');
    return 'BC1:$b64';
  }

  /// Strip whitespace that messengers / soft editors insert into pastes.
  static String scrubPayload(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), '');
  }

  /// Accept a single `BC1:` blob or pasted multi-part `BC1C:` chunks.
  ///
  /// Tolerates newlines/spaces inside base64 and between chunk lines.
  static String normalizeIncoming(String raw) {
    final text = raw.trim();
    final headerRe = RegExp(r'BC1C:\s*(\d+)\s*/\s*(\d+)\s*:');
    final headers = headerRe.allMatches(text).toList();
    if (headers.isNotEmpty) {
      final parts = <String>[];
      for (var i = 0; i < headers.length; i++) {
        final m = headers[i];
        final bodyStart = m.end;
        final bodyEnd =
            i + 1 < headers.length ? headers[i + 1].start : text.length;
        final body = scrubPayload(text.substring(bodyStart, bodyEnd));
        parts.add('BC1C:${m.group(1)}/${m.group(2)}:$body');
      }
      return joinChunks(parts);
    }

    // Single BC1: — find marker and scrub whitespace in the base64 tail.
    final marker = text.indexOf('BC1:');
    if (marker >= 0) {
      final after = text.substring(marker + 4);
      // Stop if someone pasted trailing junk after a lone BC1 (no chunks).
      return 'BC1:${scrubPayload(after)}';
    }
    return text;
  }

  static Map<String, dynamic> decodeEnvelope(String raw) {
    final rawLen = raw.length;
    var text = normalizeIncoming(raw);
    blushLog(
      'RTC',
      'decodeEnvelope rawChars=$rawLen normalizedChars=${text.length} '
      'prefix=${text.length > 8 ? text.substring(0, 8) : text}',
    );
    if (text.startsWith('BC1C:')) {
      throw const FormatException(
        'Incomplete multi-part invite. Paste every BC1C: part, or Copy the full invite once.',
      );
    }
    if (!text.startsWith('BC1:')) {
      throw const FormatException(
        'Not a Blushcraft invite (missing BC1: prefix). Copy the full invite text.',
      );
    }
    final b64 = _padBase64(text.substring(4));
    late final List<int> compressed;
    try {
      compressed = base64Url.decode(b64);
    } on FormatException {
      throw const FormatException(
        'Invite looks truncated or corrupted. Copy again from the host and paste the full text.',
      );
    }
    late final List<int> jsonBytes;
    try {
      jsonBytes = gzip.decode(compressed);
    } catch (_) {
      throw const FormatException(
        'Invite could not be decompressed (truncated paste?). Copy the full BC1: text.',
      );
    }
    final map = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
    if (map['v'] != 1) {
      throw FormatException('Unsupported invite version: ${map['v']}');
    }
    if (map['pkg'] != null && map['pkg'] != packageId) {
      throw const FormatException('Invite is for a different app package');
    }
    return map;
  }

  /// Human-readable preview after a successful decode (for paste UX).
  static String describeEnvelope(Map<String, dynamic> map) {
    final role = map['role'] ?? '?';
    final name = map['name'] ?? '?';
    final session = '${map['session'] ?? ''}';
    final short = session.length > 8 ? session.substring(0, 8) : session;
    return '$role from $name · session $short…';
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

  /// Clipboard / Share form: always the full single `BC1:` blob.
  ///
  /// Do **not** split into `BC1C:` QR chunks here — messengers and paste UIs
  /// often keep only the first ~900 chars, which then fails as "1 of 2 parts".
  /// Multi-part is only for on-screen QR paging via [chunk].
  static String clipboardText(String payload) => payload.trim();

  /// Reassemble [chunk] parts or return a single BC1 payload as-is.
  static String joinChunks(List<String> parts) {
    if (parts.isEmpty) {
      throw const FormatException('No invite parts to join');
    }
    if (parts.length == 1 && parts.first.trim().startsWith('BC1:')) {
      return 'BC1:${scrubPayload(parts.first.trim().substring(4))}';
    }
    final re = RegExp(r'^BC1C:(\d+)/(\d+):(.*)$');
    final sorted = <int, String>{};
    var total = 0;
    for (final p in parts) {
      final m = re.firstMatch(p.trim());
      if (m == null) {
        throw const FormatException('Invalid chunk (expected BC1C:i/n:…)');
      }
      total = int.parse(m.group(2)!);
      // Chunk bodies are slices of the full BC1:… string — do not scrub yet
      // (would remove nothing useful mid-slice except accidental newlines).
      sorted[int.parse(m.group(1)!)] = m.group(3)!.replaceAll(RegExp(r'\s+'), '');
    }
    if (sorted.length != total) {
      final have = sorted.keys.toList()..sort();
      throw FormatException(
        'Incomplete invite: have ${sorted.length} of $total parts '
        '(got ${have.join(", ")}). '
        'On the host, tap Copy (full invite) — not a single QR part — then Paste again.',
      );
    }
    final buf = StringBuffer();
    for (var i = 1; i <= total; i++) {
      buf.write(sorted[i]);
    }
    return normalizeIncoming(buf.toString());
  }
}

/// Collects numbered `BC1C:` (or a single `BC1:`) scans until the set is complete.
class QrChunkBag {
  final Map<int, String> parts = {};
  int? expectedTotal;

  int get haveCount => parts.length;
  int get totalCount => expectedTotal ?? 0;
  bool get isComplete =>
      expectedTotal != null && expectedTotal! > 0 && parts.length >= expectedTotal!;

  /// `true` if this string filled a new slot.
  bool add(String raw) {
    final text = raw.trim();
    if (text.startsWith('BC1C:')) {
      final m = RegExp(r'^BC1C:(\d+)/(\d+):').firstMatch(text);
      if (m == null) return false;
      final index = int.parse(m.group(1)!);
      final total = int.parse(m.group(2)!);
      expectedTotal = total;
      if (parts.containsKey(index)) return false;
      parts[index] = text;
      return true;
    }
    if (text.contains('BC1:')) {
      if (parts.isNotEmpty) return false;
      expectedTotal = 1;
      parts[1] = text;
      return true;
    }
    return false;
  }

  String join() => SdpQrCodec.joinChunks(parts.values.toList());
}
