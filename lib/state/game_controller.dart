import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/card_repository.dart';
import '../models/card.dart';
import '../models/game_mode.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/round_result.dart';
import '../networking/game_message.dart';
import '../util/blush_log.dart';
import 'stats_store.dart';

typedef SendMessage = Future<void> Function(GameMessage message);
typedef OnPeerFrame = void Function(String playerId, String base64Jpeg);
typedef OnPeerAudio = void Function(String playerId, String base64Aac);
typedef OnAvPrivacy = void Function(
  String playerId, {
  required bool cameraEnabled,
  required bool micEnabled,
});

/// Host-authoritative game logic. Guests apply [StateSyncMessage] snapshots.
class GameController extends ChangeNotifier {
  GameController({
    required CardRepository cards,
    required StatsStore stats,
    required this.displayName,
    this.isHost = true,
    this.dryRun = false,
    double riskayLevel = 0.5,
    GameMode gameMode = GameMode.romantic,
  })  : _cards = cards,
        _stats = stats,
        _riskayLevel = riskayLevel.clamp(0.0, 1.0),
        _gameMode = gameMode == GameMode.bff ? GameMode.romantic : gameMode,
        localPlayerId = const Uuid().v4();

  final CardRepository _cards;
  final StatsStore _stats;
  final String displayName;
  final bool isHost;
  final bool dryRun;
  final String localPlayerId;
  double _riskayLevel;
  GameMode _gameMode;

  SendMessage? sendMessage;
  OnPeerFrame? onPeerFrame;
  OnPeerAudio? onPeerAudio;
  OnAvPrivacy? onAvPrivacy;

  GameState? _state;
  List<int> _statementDeck = [];
  List<int> _choiceDeck = [];
  List<int> _activeStatementIds = [];
  List<int> _activeChoiceIds = [];
  GamePhase? _pausedPhase;
  final _rng = Random();

  GameState? get state => _state;
  bool get hasGame => _state != null;
  double get riskayLevel => _riskayLevel;
  GameMode get gameMode => _gameMode;

  /// Guest endpoint id for dry-run second seat.
  static const dryRunGuestId = 'dryrun-guest';

  Future<void> initLobby({String? guestName}) async {
    _state = GameState(
      phase: GamePhase.lobby,
      host: PlayerInfo(
        id: isHost ? localPlayerId : 'pending-host',
        name: isHost ? displayName : 'Host',
      ),
      guest: PlayerInfo(
        id: isHost
            ? (dryRun ? dryRunGuestId : 'pending-guest')
            : localPlayerId,
        name: isHost
            ? (guestName ?? (dryRun ? 'Partner' : 'Waiting…'))
            : displayName,
      ),
      localPlayerId: localPlayerId,
      riskayLevel: _riskayLevel,
      gameMode: _gameMode,
      message: dryRun
          ? 'Dry-run: play both seats on this device.'
          : (isHost
              ? 'Waiting for a partner to join…'
              : 'Searching for a host…'),
    );

    notifyListeners();
    if (isHost) await _broadcast();
  }

  void attachGuest({required String guestId, required String guestName}) {
    if (!isHost || _state == null) return;
    _state = _state!.copyWith(
      guest: PlayerInfo(id: guestId, name: guestName),
      message: '$guestName joined. Ready to blush?',
    );
    notifyListeners();
    _broadcast();
  }

  void renameLocal(String name) {
    if (_state == null) return;
    if (isHost) {
      _state = _state!.copyWith(host: _state!.host.copyWith(name: name));
      _broadcast();
    } else {
      sendMessage?.call(SetNameMessage(playerId: localPlayerId, name: name));
    }
    notifyListeners();
  }

  Future<void> setRiskayLevel(double level) async {
    _riskayLevel = level.clamp(0.0, 1.0);
    if (_state != null) {
      _state = _state!.copyWith(riskayLevel: _riskayLevel);
    }
    notifyListeners();
    if (isHost) {
      await _broadcast();
    } else {
      await sendMessage?.call(SetRiskayMessage(riskayLevel: _riskayLevel));
    }
  }

  Future<void> setGameMode(GameMode mode) async {
    if (!mode.isSelectable) return;
    _gameMode = mode;
    if (_state != null) {
      _state = _state!.copyWith(gameMode: _gameMode);
    }
    notifyListeners();
    if (isHost) {
      await _broadcast();
    } else {
      await sendMessage?.call(SetGameModeMessage(gameMode: _gameMode.wireName));
    }
  }

  Future<void> startGame() async {
    if (!isHost || _state == null) return;
    if (!dryRun && _state!.guest.id == 'pending-guest') return;

    final pool = _cards.poolFor(_gameMode, _riskayLevel, random: _rng);
    _activeStatementIds = pool.statements.map((s) => s.id).toList();
    _activeChoiceIds = pool.choices.map((c) => c.id).toList();
    _statementDeck = List<int>.from(_activeStatementIds)..shuffle(_rng);
    _choiceDeck = List<int>.from(_activeChoiceIds)..shuffle(_rng);

    final hostHand = _draw(7);
    final guestHand = _draw(7);

    _state = _state!.copyWith(
      host: _state!.host.copyWith(score: 0),
      guest: _state!.guest.copyWith(score: 0),
      hostHand: hostHand,
      guestHand: guestHand,
      roundNumber: 0,
      riskayLevel: _riskayLevel,
      gameMode: _gameMode,
      clearPrize: true,
      clearLastCombo: true,
    );

    await _startRound();
  }

  Future<void> _startRound() async {
    if (_statementDeck.isEmpty) {
      _statementDeck = List<int>.from(_activeStatementIds)..shuffle(_rng);
    }
    final sid = _statementDeck.removeLast();
    final statement = _cards.statementById(sid, mode: _gameMode)!;

    _state = _state!.copyWith(
      phase: GamePhase.selecting,
      statementId: sid,
      statementText: statement.text,
      roundNumber: _state!.roundNumber + 1,
      clearSubmissions: true,
      clearVotes: true,
      message: 'Pick your blush-worthy choice.',
    );
    notifyListeners();
    await _broadcast();
  }

  List<int> _draw(int n) {
    final out = <int>[];
    for (var i = 0; i < n; i++) {
      if (_choiceDeck.isEmpty) {
        _choiceDeck = List<int>.from(_activeChoiceIds)..shuffle(_rng);
      }
      out.add(_choiceDeck.removeLast());
    }
    return out;
  }

  Future<void> submitChoice(int choiceId, {String? asPlayerId}) async {
    if (_state == null) return;
    final playerId = asPlayerId ??
        (dryRun && _state!.phase == GamePhase.selecting
            ? _nextDryRunSubmitter()
            : localPlayerId);

    if (!isHost && !dryRun) {
      blushLog('Game', 'guest submit choice=$choiceId phase=${_state!.phase.name}');
      await sendMessage?.call(
        SubmitChoiceMessage(playerId: localPlayerId, choiceId: choiceId),
      );
      // Optimistic wait — mark local submission so UI locks (host sync follows).
      final asGuest = localPlayerId == _state!.guest.id;
      _state = _state!.copyWith(
        phase: GamePhase.waitingForOpponent,
        message: 'Waiting for your partner…',
        guestSubmittedChoiceId: asGuest ? choiceId : null,
        hostSubmittedChoiceId: asGuest ? null : choiceId,
      );
      notifyListeners();
      return;
    }

    await _applySubmit(playerId, choiceId);
  }

  String _nextDryRunSubmitter() {
    // Host submits first if not yet submitted, else guest.
    if (_state!.hostSubmittedChoiceId == null) return _state!.host.id;
    return _state!.guest.id;
  }

  Future<void> _applySubmit(String playerId, int choiceId) async {
    if (_state == null || !isHost) return;
    final choice = _cards.choiceById(choiceId, mode: _gameMode);
    if (choice == null) {
      blushLog('Game', 'submit ignored: unknown choice=$choiceId');
      return;
    }

    final isHostPlayer = playerId == _state!.host.id;
    final hand = List<int>.from(isHostPlayer ? _state!.hostHand : _state!.guestHand);
    if (!hand.contains(choiceId)) {
      blushLog(
        'Game',
        'submit ignored: choice=$choiceId not in '
        '${isHostPlayer ? 'host' : 'guest'} hand=$hand',
      );
      return;
    }
    if (isHostPlayer && _state!.hostSubmittedChoiceId != null) {
      blushLog('Game', 'submit ignored: host already submitted');
      return;
    }
    if (!isHostPlayer && _state!.guestSubmittedChoiceId != null) {
      blushLog('Game', 'submit ignored: guest already submitted');
      return;
    }

    hand.remove(choiceId);

    if (isHostPlayer) {
      _state = _state!.copyWith(
        hostHand: hand,
        hostSubmittedChoiceId: choiceId,
        hostSubmittedChoiceText: choice.text,
      );
    } else {
      _state = _state!.copyWith(
        guestHand: hand,
        guestSubmittedChoiceId: choiceId,
        guestSubmittedChoiceText: choice.text,
      );
    }

    if (_state!.bothSubmitted) {
      _state = _state!.copyWith(
        phase: GamePhase.reveal,
        message: 'Read your lines aloud, then look each other in the eye.',
      );
      blushLog('Game', 'both submitted → reveal');
    } else {
      _state = _state!.copyWith(
        phase: dryRun ? GamePhase.selecting : GamePhase.waitingForOpponent,
        message: dryRun
            ? 'Now pick for ${_state!.guest.name}…'
            : 'Waiting for your partner…',
      );
      blushLog(
        'Game',
        '${isHostPlayer ? 'host' : 'guest'} submitted → ${_state!.phase.name}',
      );
    }

    notifyListeners();
    await _broadcast();
  }

  Future<void> continueToReaction() async {
    if (_state == null || !isHost) {
      if (_state != null && !isHost) {
        // Guest just follows host phase; no-op
      }
      return;
    }
    if (_state!.phase != GamePhase.reveal) return;
    _state = _state!.copyWith(
      phase: GamePhase.reaction,
      clearVotes: true,
      message: 'Who blushed, laughed, or broke eye contact first?',
    );
    blushLog('Game', 'reveal → reaction');
    notifyListeners();
    await _broadcast();
  }

  /// [winnerId] is the player who did NOT react first (gets the point).
  Future<void> voteReactionWinner(String winnerId, {String? asVoterId}) async {
    if (_state == null) return;
    final voterId = asVoterId ??
        (dryRun ? _nextDryRunVoter() : localPlayerId);

    if (!isHost && !dryRun) {
      await sendMessage?.call(
        ReactionVoteMessage(voterId: localPlayerId, winnerId: winnerId),
      );
      return;
    }

    await _applyVote(voterId, winnerId);
  }

  String _nextDryRunVoter() {
    if (_state!.hostReactionVote == null) return _state!.host.id;
    return _state!.guest.id;
  }

  Future<void> _applyVote(String voterId, String winnerId) async {
    if (_state == null || !isHost) return;

    if (voterId == _state!.host.id) {
      _state = _state!.copyWith(hostReactionVote: winnerId);
    } else {
      _state = _state!.copyWith(guestReactionVote: winnerId);
    }

    if (_state!.bothVoted) {
      if (_state!.votesAgree) {
        await _awardPoint(_state!.hostReactionVote!);
      } else {
        _state = _state!.copyWith(
          clearVotes: true,
          message: 'No agreement: read again while holding eye contact!',
        );
      }
    } else {
      _state = _state!.copyWith(
        message: dryRun
            ? 'Confirm from the other seat…'
            : 'Waiting for partner to confirm…',
      );
    }

    notifyListeners();
    await _broadcast();
  }

  Future<void> _awardPoint(String winnerId) async {
    final s = _state!;
    final hostWins = winnerId == s.host.id;
    final host = hostWins ? s.host.copyWith(score: s.host.score + 1) : s.host;
    final guest = !hostWins ? s.guest.copyWith(score: s.guest.score + 1) : s.guest;

    final combo = RoundCombo(
      statementText: s.statementText!,
      statementId: s.statementId!,
      hostChoiceText: s.hostSubmittedChoiceText!,
      hostChoiceId: s.hostSubmittedChoiceId!,
      guestChoiceText: s.guestSubmittedChoiceText!,
      guestChoiceId: s.guestSubmittedChoiceId!,
      winnerId: winnerId,
      winnerName: hostWins ? host.name : guest.name,
    );

    await _stats.recordCombo(combo);

    // Refill hands to 7
    var hostHand = List<int>.from(s.hostHand);
    var guestHand = List<int>.from(s.guestHand);
    while (hostHand.length < 7) {
      hostHand.addAll(_draw(1));
    }
    while (guestHand.length < 7) {
      guestHand.addAll(_draw(1));
    }

    final gameOver =
        host.score >= s.pointsToWin || guest.score >= s.pointsToWin;

    _state = s.copyWith(
      host: host,
      guest: guest,
      hostHand: hostHand,
      guestHand: guestHand,
      lastCombo: combo,
      phase: gameOver ? GamePhase.gameOver : GamePhase.roundResult,
      message: gameOver
          ? '${hostWins ? host.name : guest.name} wins Blushcraft!'
          : '${hostWins ? host.name : guest.name} takes the point.',
      clearSubmissions: true,
      clearVotes: true,
    );

    if (gameOver) {
      final localIsHost = s.localPlayerId == s.host.id;
      final localWon = localIsHost
          ? host.score >= s.pointsToWin
          : guest.score >= s.pointsToWin;
      await _stats.recordGameResult(
        won: localWon,
        hostScore: host.score,
        guestScore: guest.score,
      );
    }

    notifyListeners();
    await _broadcast();
  }

  Future<void> nextRound() async {
    if (!isHost || _state == null) {
      if (!isHost) {
        await sendMessage?.call(const NextRoundMessage());
      }
      return;
    }
    if (_state!.phase != GamePhase.roundResult) return;
    await _startRound();
  }

  Future<void> setPrize(String prize) async {
    if (_state == null) return;
    if (!isHost && !dryRun) {
      await sendMessage?.call(SetPrizeMessage(prize: prize));
      return;
    }
    _state = _state!.copyWith(prize: prize);
    notifyListeners();
    await _broadcast();
  }

  /// Apply a remote message (host processes intents; guest applies state).
  Future<void> onMessage(GameMessage message) async {
    switch (message) {
      case HelloMessage m:
        if (isHost) {
          attachGuest(guestId: m.playerId, guestName: m.name);
          if (_pausedPhase != null ||
              _state?.phase == GamePhase.disconnected) {
            await resumeAfterReconnect();
          }
        }
      case SetNameMessage m:
        if (isHost && _state != null) {
          if (m.playerId == _state!.guest.id) {
            _state = _state!.copyWith(guest: _state!.guest.copyWith(name: m.name));
            notifyListeners();
            await _broadcast();
          }
        }
      case StateSyncMessage m:
        if (!isHost) {
          final remote = GameState.fromJson(m.state).forViewer(localPlayerId);
          _riskayLevel = remote.riskayLevel;
          _gameMode = remote.gameMode;
          _state = remote;
          notifyListeners();
        }
      case SubmitChoiceMessage m:
        if (isHost) await _applySubmit(m.playerId, m.choiceId);
      case ReactionVoteMessage m:
        if (isHost) await _applyVote(m.voterId, m.winnerId);
      case StartGameMessage():
        if (isHost) await startGame();
      case NextRoundMessage():
        if (isHost) await nextRound();
      case SetPrizeMessage m:
        if (isHost) {
          _state = _state?.copyWith(prize: m.prize);
          notifyListeners();
          await _broadcast();
        }
      case SetRiskayMessage m:
        if (isHost && _state?.phase == GamePhase.lobby) {
          await setRiskayLevel(m.riskayLevel);
        }
      case SetGameModeMessage m:
        if (isHost && _state?.phase == GamePhase.lobby) {
          await setGameMode(GameMode.fromWire(m.gameMode));
        }
      case PeerFrameMessage m:
        onPeerFrame?.call(m.playerId, m.base64Jpeg);
      case PeerAudioMessage m:
        onPeerAudio?.call(m.playerId, m.base64Aac);
      case AvPrivacyMessage m:
        onAvPrivacy?.call(
          m.playerId,
          cameraEnabled: m.cameraEnabled,
          micEnabled: m.micEnabled,
        );
    }
  }

  Future<void> _broadcast() async {
    if (!isHost || _state == null) return;
    final payload = StateSyncMessage(state: _state!.toJson());
    await sendMessage?.call(payload);
  }

  void markDisconnected() {
    if (_state == null) return;
    if (_state!.phase != GamePhase.disconnected) {
      _pausedPhase = _state!.phase;
    }
    _state = _state!.copyWith(
      phase: GamePhase.disconnected,
      message:
          'Connection lost. Stay on this screen; reconnecting keeps your game.',
    );
    notifyListeners();
  }

  /// Restore the in-progress phase after a Nearby reconnect.
  Future<void> resumeAfterReconnect() async {
    if (_state == null) return;
    if (_pausedPhase != null) {
      _state = _state!.copyWith(
        phase: _pausedPhase!,
        message: 'Reconnected: pick up where you left off.',
      );
      _pausedPhase = null;
    } else if (_state!.phase == GamePhase.disconnected) {
      _state = _state!.copyWith(
        phase: GamePhase.lobby,
        message: 'Reconnected.',
      );
    }
    notifyListeners();
    if (isHost) await _broadcast();
  }

  /// Dry-run: switch which seat is "active" for UI prompts (optional).
  bool get dryRunAwaitingGuestSubmit =>
      dryRun &&
      _state != null &&
      _state!.hostSubmittedChoiceId != null &&
      _state!.guestSubmittedChoiceId == null;

  bool get dryRunAwaitingGuestVote =>
      dryRun &&
      _state != null &&
      _state!.phase == GamePhase.reaction &&
      _state!.hostReactionVote != null &&
      _state!.guestReactionVote == null;

  /// Hand for the seat currently submitting (dry-run switches to guest).
  List<int> get activeHand {
    final s = _state;
    if (s == null) return const [];
    if (dryRunAwaitingGuestSubmit) return s.guestHand;
    return s.localHand;
  }

  ChoiceCard? choice(int id) => _cards.choiceById(id, mode: _gameMode);
  StatementCard? statement(int id) =>
      _cards.statementById(id, mode: _gameMode);
}
