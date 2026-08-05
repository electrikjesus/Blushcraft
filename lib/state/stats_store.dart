import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/round_result.dart';

class PlayerStats {
  const PlayerStats({
    this.gamesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.roundsPlayed = 0,
    this.recentCombos = const [],
  });

  final int gamesPlayed;
  final int wins;
  final int losses;
  final int roundsPlayed;
  final List<RoundCombo> recentCombos;

  PlayerStats copyWith({
    int? gamesPlayed,
    int? wins,
    int? losses,
    int? roundsPlayed,
    List<RoundCombo>? recentCombos,
  }) {
    return PlayerStats(
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      roundsPlayed: roundsPlayed ?? this.roundsPlayed,
      recentCombos: recentCombos ?? this.recentCombos,
    );
  }

  Map<String, dynamic> toJson() => {
        'gamesPlayed': gamesPlayed,
        'wins': wins,
        'losses': losses,
        'roundsPlayed': roundsPlayed,
        'recentCombos': recentCombos.map((c) => c.toJson()).toList(),
      };

  factory PlayerStats.fromJson(Map<String, dynamic> json) {
    return PlayerStats(
      gamesPlayed: json['gamesPlayed'] as int? ?? 0,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      roundsPlayed: json['roundsPlayed'] as int? ?? 0,
      recentCombos: (json['recentCombos'] as List<dynamic>? ?? [])
          .map((e) => RoundCombo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class StatsStore {
  StatsStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'blushcraft_stats';

  /// Tracks whether the last gameOver already counted (avoid double-count).
  bool _pendingGameResult = false;

  PlayerStats load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const PlayerStats();
    try {
      return PlayerStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PlayerStats();
    }
  }

  Future<void> _save(PlayerStats stats) async {
    await _prefs.setString(_key, jsonEncode(stats.toJson()));
  }

  Future<void> recordCombo(RoundCombo combo) async {
    final current = load();
    final combos = [combo, ...current.recentCombos].take(20).toList();
    await _save(current.copyWith(
      roundsPlayed: current.roundsPlayed + 1,
      recentCombos: combos,
    ));
  }

  Future<void> recordGameResult({
    required bool won,
    required int hostScore,
    required int guestScore,
  }) async {
    if (_pendingGameResult) return;
    _pendingGameResult = true;
    final current = load();
    await _save(current.copyWith(
      gamesPlayed: current.gamesPlayed + 1,
      wins: current.wins + (won ? 1 : 0),
      losses: current.losses + (won ? 0 : 1),
    ));
  }

  void resetGameResultGate() {
    _pendingGameResult = false;
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
    _pendingGameResult = false;
  }
}
