import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/game_state.dart';
import '../models/round_result.dart';
import '../state/stats_store.dart';

class ShareService {
  const ShareService();

  Future<void> shareText(String text, {String? subject}) {
    return SharePlus.instance.share(
      ShareParams(text: text, subject: subject ?? 'Blushcraft'),
    );
  }

  Future<void> shareCombo(RoundCombo combo) {
    return shareText(combo.toShareText(), subject: 'Blushcraft combo');
  }

  Future<void> shareGameResult(GameState state) {
    final host = state.host;
    final guest = state.guest;
    final winner = host.score >= state.pointsToWin ? host : guest;
    final prize = state.prize;
    final buf = StringBuffer()
      ..writeln('We played Blushcraft!')
      ..writeln('${host.name} ${host.score} - ${guest.score} ${guest.name}')
      ..writeln('Winner: ${winner.name}');
    if (prize != null && prize.isNotEmpty) {
      buf.writeln('Prize: $prize');
    }
    if (state.lastCombo != null) {
      buf.writeln();
      buf.writeln(state.lastCombo!.toShareText());
    }
    return SharePlus.instance.share(
      ShareParams(text: buf.toString(), subject: 'Blushcraft results'),
    );
  }

  Future<void> shareStats(PlayerStats stats) {
    final buf = StringBuffer()
      ..writeln('My Blushcraft stats')
      ..writeln('Games: ${stats.gamesPlayed}  Wins: ${stats.wins}  Losses: ${stats.losses}')
      ..writeln('Rounds played: ${stats.roundsPlayed}');
    if (stats.recentCombos.isNotEmpty) {
      buf.writeln();
      buf.writeln('Recent combo:');
      buf.writeln(stats.recentCombos.first.toShareText());
    }
    return SharePlus.instance.share(
      ShareParams(text: buf.toString(), subject: 'Blushcraft stats'),
    );
  }

  Future<void> shareImageBytes(List<int> bytes, {String? text}) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/blushcraft_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: text,
        subject: 'Blushcraft moment',
      ),
    );
  }
}
