import 'package:flutter/foundation.dart';

/// The board: which cells carry you up, which carry you down.
///
/// Comes from the server pinned to the session's board version, never
/// from a constant here -- two clients disagreeing about where a snake is
/// would be the one bug this game cannot survive.
@immutable
class SnakesBoard {
  const SnakesBoard({required this.ladders, required this.snakes});

  /// Cell -> destination, for cells that carry you up.
  final Map<int, int> ladders;

  /// Cell -> destination, for cells that carry you down.
  final Map<int, int> snakes;

  static const empty = SnakesBoard(ladders: {}, snakes: {});

  int? destinationFor(int cell) => ladders[cell] ?? snakes[cell];

  factory SnakesBoard.fromJson(Map<String, dynamic> json) {
    Map<int, int> parse(Object? raw) {
      if (raw is! Map) return const {};
      final out = <int, int>{};
      raw.forEach((key, value) {
        final from = int.tryParse('$key');
        final to = value is int ? value : int.tryParse('$value');
        if (from != null && to != null) out[from] = to;
      });
      return out;
    }

    return SnakesBoard(
      ladders: parse(json['ladders']),
      snakes: parse(json['snakes']),
    );
  }
}

/// What befell a token on one roll.
///
/// A bounce and a snake both end below where the die pointed and animate
/// completely differently -- one walks up and comes back, the other
/// slides down a curve -- so the server names which happened rather than
/// leaving the client to re-derive it from a board that may have been
/// retuned since.
enum SnakesMovement {
  normal,
  bounce,
  ladder,
  snake;

  static SnakesMovement fromWire(String? raw) => switch (raw) {
    'bounce' => SnakesMovement.bounce,
    'ladder' => SnakesMovement.ladder,
    'snake' => SnakesMovement.snake,
    _ => SnakesMovement.normal,
  };

  bool get isFeature =>
      this == SnakesMovement.ladder || this == SnakesMovement.snake;
}

/// One roll, with everything the replay needs to animate it.
@immutable
class SnakesTurn {
  const SnakesTurn({
    required this.roundNumber,
    required this.playerId,
    required this.dieRoll,
    required this.movedFrom,
    required this.rolledTo,
    required this.movedTo,
    required this.movement,
    this.didBounce = false,
  });

  final int roundNumber;
  final String playerId;
  final int dieRoll;

  /// Where the token started.
  final int movedFrom;

  /// Where the die alone put it, before any snake or ladder. The walk
  /// animates to here first.
  final int rolledTo;

  /// Where it ended.
  final int movedTo;

  final SnakesMovement movement;

  /// The roll overshot 100 and came back. Independent of [movement]: a
  /// turn can bounce, hit a feature, or do both in that order, and the
  /// animation must show all of it.
  final bool didBounce;

  factory SnakesTurn.fromJson(Map<String, dynamic> json) => SnakesTurn(
    roundNumber: _asInt(json['round_number']),
    playerId: '${json['active_partner_id'] ?? ''}',
    dieRoll: _asInt(json['die_roll']),
    movedFrom: _asInt(json['moved_from']),
    rolledTo: _asInt(json['rolled_to']),
    movedTo: _asInt(json['moved_to']),
    movement: SnakesMovement.fromWire(json['movement_kind'] as String?),
    didBounce: json['did_bounce'] == true,
  );
}

/// A session as the client sees it.
@immutable
class SnakesSession {
  const SnakesSession({
    required this.sessionId,
    required this.status,
    required this.userA,
    required this.userB,
    required this.positionA,
    required this.positionB,
    required this.currentRound,
    required this.currentTurnUserId,
    required this.winnerUserId,
    required this.board,
    required this.turns,
  });

  final String sessionId;
  final String status;
  final String userA;
  final String userB;
  final int positionA;
  final int positionB;
  final int currentRound;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final SnakesBoard board;

  /// Most recent first from the server; the replay reads the last one.
  final List<SnakesTurn> turns;

  bool get isActive => status == 'active';
  bool get isFinished => status == 'completed';
  bool isMyTurn(String? userId) =>
      userId != null && currentTurnUserId == userId;

  int positionFor(String? userId) => userId == userA ? positionA : positionB;
  int partnerPositionFor(String? userId) =>
      userId == userA ? positionB : positionA;

  /// The turn a returning player has not watched yet, if any.
  SnakesTurn? get lastTurn => turns.isEmpty ? null : turns.last;

  SnakesSession copyWith({int? positionA, int? positionB}) => SnakesSession(
    sessionId: sessionId,
    status: status,
    userA: userA,
    userB: userB,
    positionA: positionA ?? this.positionA,
    positionB: positionB ?? this.positionB,
    currentRound: currentRound,
    currentTurnUserId: currentTurnUserId,
    winnerUserId: winnerUserId,
    board: board,
    turns: turns,
  );

  factory SnakesSession.fromJson(Map<String, dynamic> json) => SnakesSession(
    sessionId: '${json['session_id'] ?? ''}',
    status: '${json['status'] ?? 'invited'}',
    userA: '${json['user_a'] ?? ''}',
    userB: '${json['user_b'] ?? ''}',
    positionA: _asInt(json['position_a']),
    positionB: _asInt(json['position_b']),
    currentRound: _asInt(json['current_round'], fallback: 1),
    currentTurnUserId: json['current_turn_user_id'] as String?,
    winnerUserId: json['winner_user_id'] as String?,
    board:
        json['board'] is Map
            ? SnakesBoard.fromJson(
              Map<String, dynamic>.from(json['board'] as Map),
            )
            : SnakesBoard.empty,
    turns:
        (json['rounds'] as List?)
            ?.whereType<Map>()
            .map((e) => SnakesTurn.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
  );
}

/// Server-side refusals, already carrying a user-facing message.
@immutable
class SnakesApiError implements Exception {
  const SnakesApiError({required this.code, required this.message});

  final String code;
  final String message;

  factory SnakesApiError.fromJson(Map<String, dynamic> json) => SnakesApiError(
    code: '${json['code'] ?? 'UNKNOWN'}',
    // The server writes these for players; the client never composes its
    // own from an exception, which is how internals leak into a UI.
    message: '${json['message'] ?? 'Something went wrong. Please try again.'}',
  );

  @override
  String toString() => message;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}
