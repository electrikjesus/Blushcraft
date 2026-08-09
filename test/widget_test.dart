import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:blushcraft/data/card_repository.dart';
import 'package:blushcraft/models/card.dart';
import 'package:blushcraft/models/game_mode.dart';
import 'package:blushcraft/networking/webrtc/sdp_qr_codec.dart';

void main() {
  test('SdpQrCodec round-trips and joins pasted chunks', () {
    final payload = SdpQrCodec.encodeEnvelope(
      role: 'offer',
      sessionId: 'sess-1',
      displayName: 'Player',
      sdp: 'v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n',
      ice: [
        '{"candidate":"candidate:1 1 UDP 2122252543 10.0.0.1 54400 typ host","sdpMid":"0","sdpMLineIndex":0}',
      ],
    );
    expect(payload.startsWith('BC1:'), isTrue);
    final decoded = SdpQrCodec.decodeEnvelope(payload);
    expect(decoded['role'], 'offer');
    expect(decoded['session'], 'sess-1');

    final parts = SdpQrCodec.chunk(payload, size: 40);
    expect(parts.length, greaterThan(1));
    expect(parts.first.startsWith('BC1C:'), isTrue);
    final joined = SdpQrCodec.normalizeIncoming(parts.join('\n'));
    expect(SdpQrCodec.decodeEnvelope(joined)['session'], 'sess-1');

    // Messy paste: whitespace inside base64 and between chunks.
    final messySingle = payload.replaceAllMapped(
      RegExp(r'(.{16})'),
      (m) => '${m[1]}\n',
    );
    expect(SdpQrCodec.decodeEnvelope(messySingle)['session'], 'sess-1');

    final messyChunks = parts.map((p) {
      final i = p.indexOf(':', 5); // after BC1C:
      // Insert spaces into body.
      final head = p.substring(0, i + 1);
      final body = p.substring(i + 1);
      return '$head${body.splitMapJoin(RegExp(r'.{8}'), onMatch: (m) => '${m[0]} ', onNonMatch: (s) => s)}';
    }).join('\n\n');
    expect(
      SdpQrCodec.decodeEnvelope(SdpQrCodec.normalizeIncoming(messyChunks))['session'],
      'sess-1',
    );

    expect(
      () => SdpQrCodec.joinChunks(parts.take(1).toList()),
      throwsA(isA<FormatException>()),
    );
  });

  test('StatementCard fills first blank only', () {
    const s = StatementCard(
      id: 15,
      text: 'If you _______________ right now, I\'d _______________.',
    );
    expect(
      s.fillWith('smile'),
      "If you smile right now, I'd ….",
    );
  });

  test('StatementCard normalizes mid-sentence choice casing', () {
    const s = StatementCard(
      id: 1,
      text: 'I love it most when you look at me like _______________.',
    );
    expect(
      s.fillWith('A slow dance in the kitchen.'),
      'I love it most when you look at me like a slow dance in the kitchen.',
    );
  });

  test('StatementCard keeps sentence-initial choice casing', () {
    const s = StatementCard(
      id: 26,
      text: '_______________ makes my heart race.',
    );
    expect(
      s.fillWith('A slow dance in the kitchen.'),
      'A slow dance in the kitchen makes my heart race.',
    );
  });

  test('Riskay pool mixes packs by slider', () {
    final repo = CardRepository.forTesting(
      romanticStatements: [
        const StatementCard(id: 1, text: 'd', heat: CardHeat.defaults),
        const StatementCard(id: 2, text: 'i', heat: CardHeat.innocent),
        const StatementCard(id: 3, text: 'p', heat: CardHeat.provocative),
      ],
      romanticChoices: [
        const ChoiceCard(id: 1, text: 'd', heat: CardHeat.defaults),
        const ChoiceCard(id: 2, text: 'i', heat: CardHeat.innocent),
        const ChoiceCard(id: 3, text: 'p', heat: CardHeat.provocative),
      ],
    );

    final mid = repo.poolForRiskay(0.5, random: Random(1));
    expect(mid.statements.every((s) => s.heat == CardHeat.defaults), isTrue);
    expect(mid.choices.every((c) => c.heat == CardHeat.defaults), isTrue);

    final soft = repo.poolForRiskay(0.0, random: Random(1));
    expect(soft.statements.any((s) => s.heat == CardHeat.innocent), isTrue);
    expect(soft.statements.any((s) => s.heat == CardHeat.provocative), isFalse);

    final hot = repo.poolForRiskay(1.0, random: Random(1));
    expect(hot.statements.any((s) => s.heat == CardHeat.provocative), isTrue);
    expect(hot.statements.any((s) => s.heat == CardHeat.innocent), isFalse);
  });

  test('Mode pools do not cross-contaminate', () {
    final repo = CardRepository.forTesting(
      romanticStatements: [
        const StatementCard(
          id: 1,
          text: 'romantic default',
          heat: CardHeat.defaults,
        ),
      ],
      romanticChoices: [
        const ChoiceCard(id: 1, text: 'romantic choice', heat: CardHeat.defaults),
      ],
      freshStatements: [
        const StatementCard(
          id: 1,
          text: 'fresh default',
          heat: CardHeat.defaults,
        ),
        const StatementCard(
          id: 2,
          text: 'fresh innocent',
          heat: CardHeat.innocent,
        ),
      ],
      freshChoices: [
        const ChoiceCard(id: 1, text: 'fresh choice', heat: CardHeat.defaults),
      ],
    );

    final romantic = repo.poolFor(GameMode.romantic, 0.5, random: Random(1));
    expect(romantic.statements.map((s) => s.text), ['romantic default']);
    expect(romantic.choices.map((c) => c.text), ['romantic choice']);

    final fresh = repo.poolFor(GameMode.freshStart, 0.0, random: Random(1));
    expect(fresh.statements.any((s) => s.text.contains('romantic')), isFalse);
    expect(fresh.statements.any((s) => s.text.contains('fresh')), isTrue);
    expect(
      repo.statementById(1, mode: GameMode.freshStart)?.text,
      'fresh default',
    );
    expect(
      repo.statementById(1, mode: GameMode.romantic)?.text,
      'romantic default',
    );
  });

  test('Riskay labels', () {
    expect(CardRepository.labelForRiskay(0.0), 'Innocent');
    expect(CardRepository.labelForRiskay(0.5), 'Blush');
    expect(CardRepository.labelForRiskay(1.0), 'Riskay');
  });

  test('Deck statements use NP/gerund blank lead-ins', () {
    const packs = [
      'assets/cards.json',
      'assets/cards_fresh_start.json',
    ];
    for (final path in packs) {
      final json =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      final statements = json['statements'] as List<dynamic>;
      for (final raw in statements) {
        final s = raw as Map<String, dynamic>;
        final id = s['id'];
        final text = s['text'] as String;
        final issues = blankLeadInIssues(text);
        expect(
          issues,
          isEmpty,
          reason: '$path id=$id: $text → $issues',
        );
      }
    }
  });
}

/// Words that may precede `to ___` when the blank is an NP/gerund slot.
const _allowedToLeadWords = {
  'comes',
  'asleep',
  'related',
  'try',
  'reacts',
  'listen',
  'listens',
  'accustomed',
  'used',
  'due',
  'up',
  'according',
};

/// Returns authoring-rule violations for [text], or empty if OK.
List<String> blankLeadInIssues(String text) {
  final issues = <String>[];
  final blanks = RegExp(r'_+').allMatches(text).toList();
  if (blanks.length > 1) {
    issues.add('multiple_blanks');
  }
  if (blanks.isEmpty) {
    issues.add('missing_blank');
    return issues;
  }

  for (final m in blanks) {
    final before = text.substring(0, m.start);
    final words = before
        .trimRight()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.replaceAll(RegExp(r"[^\w']"), '').toLowerCase())
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) continue; // sentence-initial blank is OK

    final last = words.last;
    final prev = words.length >= 2 ? words[words.length - 2] : null;

    if (last == 'to' && (prev == null || !_allowedToLeadWords.contains(prev))) {
      issues.add('bare_infinitive_to');
    }
    if (last == 'you' || last == 'we') {
      issues.add('bare_pronoun_verb');
    }
    if ({
      "won't",
      'will',
      "can't",
      'cannot',
      'should',
      'could',
      'would',
      "didn't",
      "don't",
      'and',
    }.contains(last)) {
      issues.add('bare_aux_or_and');
    }
    if (last == 'incredibly') {
      issues.add('adjective_only');
    }
    if (last == 'your') {
      issues.add('bare_possessive_your');
    }
    if (prev == 'when' && last == 'you') {
      issues.add('when_you_verb');
    }
    if (prev == 'way' && last == 'you') {
      issues.add('way_you_verb');
    }
    if (last == 'who') {
      issues.add('who_verb');
    }
    if (prev == 'whether' && last == 'you') {
      issues.add('whether_you_verb');
    }
    if (prev == 'that' && last == 'you') {
      issues.add('that_you_verb');
    }
    if (prev == 'hoping' && last == 'you') {
      issues.add('hoping_you_verb');
    }
  }
  return issues;
}
