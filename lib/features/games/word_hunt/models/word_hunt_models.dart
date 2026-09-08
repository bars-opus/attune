import 'package:flutter/foundation.dart';

/// One cell of the grid, by row and column.
///
/// A plain record would do, but the drag path is compared, deduplicated
/// and sent to the server, and value equality on a named type is what
/// makes all three read the same way.
@immutable
class WordHuntCell {
  const WordHuntCell(this.row, this.col);

  final int row;
  final int col;

  bool get inBounds => row >= 0 && row < 10 && col >= 0 && col < 10;

  List<int> toJson() => [row, col];

  static WordHuntCell? fromJson(Object? raw) {
    if (raw is! List || raw.length != 2) return null;
    final row = raw[0] is int ? raw[0] as int : int.tryParse('${raw[0]}');
    final col = raw[1] is int ? raw[1] as int : int.tryParse('${raw[1]}');
    if (row == null || col == null) return null;
    return WordHuntCell(row, col);
  }

  @override
  bool operator ==(Object other) =>
      other is WordHuntCell && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => '($row,$col)';
}

/// How one player's attempt ended.
///
/// Four states, not a boolean: a timeout is not a surrender. The UI shows
/// the last three identically as "did not find it" -- reporting a quit as
/// a quit would turn a kindness into something to be embarrassed about --
/// but the distinction has to survive the wire to be there at all.
enum WordHuntStatus {
  inProgress,
  found,
  gaveUp,
  timedOut,

  /// No attempt row at all: the session ended before they ever started.
  didNotPlay;

  static WordHuntStatus fromWire(String? raw) => switch (raw) {
    'found' => WordHuntStatus.found,
    'gave_up' => WordHuntStatus.gaveUp,
    'timed_out' => WordHuntStatus.timedOut,
    'did_not_play' => WordHuntStatus.didNotPlay,
    _ => WordHuntStatus.inProgress,
  };

  bool get isTerminal => this != WordHuntStatus.inProgress;
  bool get foundIt => this == WordHuntStatus.found;
}

/// Everything the server is willing to tell this player right now.
///
/// The absences matter as much as the values. Before Start there is no
/// grid and no word; until both attempts are terminal there is no partner
/// timing; until the session is over there is no placement. Each of those
/// is a null here because the key was ABSENT from the response, not
/// because it was sent as null -- see the spec's §10.
@immutable
class WordHuntSession {
  const WordHuntSession({
    required this.sessionId,
    required this.relationshipId,
    required this.initiatorId,
    required this.status,
    required this.userA,
    required this.userB,
    required this.partnerId,
    required this.wordLength,
    required this.serverObservedAt,
    required this.bothTerminal,
    this.grid,
    this.word,
    this.myStatus = WordHuntStatus.inProgress,
    this.myStartedAt,
    this.myDeadlineAt,
    this.myElapsedMs,
    this.partnerStatus,
    this.partnerElapsedMs,
    this.placement,
  });

  final String sessionId;
  final String relationshipId;
  final String initiatorId;

  /// The session's lifecycle: invited, active, completed, abandoned.
  final String status;

  final String userA;
  final String userB;
  final String partnerId;

  /// Known before Start so the lobby can say how long the word is without
  /// giving away what it is.
  final int wordLength;

  /// Captured server-side just before the response was built. Paired with
  /// [myStartedAt] this is what the display clock is seeded from -- the
  /// device wall clock is never trusted.
  final DateTime serverObservedAt;

  final bool bothTerminal;

  /// Ten strings of ten uppercase letters. Null until this player starts.
  final List<String>? grid;

  /// Null until this player starts, for the same reason.
  final String? word;

  final WordHuntStatus myStatus;
  final DateTime? myStartedAt;
  final DateTime? myDeadlineAt;
  final int? myElapsedMs;

  /// Null until BOTH attempts are terminal.
  final WordHuntStatus? partnerStatus;
  final int? partnerElapsedMs;

  /// Where the word was. Null until the session is over, then shown to
  /// both players including whoever did not find it.
  final List<WordHuntCell>? placement;

  bool get hasStarted => myStartedAt != null;
  bool get isOver => status == 'completed' || status == 'abandoned';
  bool get isInvited => status == 'invited';
  bool get isActive => status == 'active';

  /// True once this player is done but the reveal has not opened, which
  /// is the only state the waiting screen exists for.
  bool get isWaitingForPartner => myStatus.isTerminal && !bothTerminal;

  factory WordHuntSession.fromJson(Map<String, dynamic> json) {
    DateTime? time(Object? raw) =>
        raw == null ? null : DateTime.tryParse('$raw')?.toUtc();

    List<String>? parseGrid(Object? raw) {
      if (raw is! List) return null;
      final rows = raw.map((r) => '$r').toList(growable: false);
      // A grid that is not ten rows of ten is not renderable, and drawing
      // a partial one would put letters at coordinates the server does
      // not agree with.
      if (rows.length != 10 || rows.any((r) => r.length != 10)) return null;
      return rows;
    }

    List<WordHuntCell>? parsePlacement(Object? raw) {
      if (raw is! List) return null;
      final cells = <WordHuntCell>[];
      for (final entry in raw) {
        final cell = WordHuntCell.fromJson(entry);
        if (cell == null || !cell.inBounds) return null;
        cells.add(cell);
      }
      return cells.isEmpty ? null : cells;
    }

    int? asInt(Object? raw) =>
        raw is int ? raw : (raw == null ? null : int.tryParse('$raw'));

    return WordHuntSession(
      sessionId: '${json['session_id']}',
      relationshipId: '${json['relationship_id']}',
      initiatorId: '${json['initiator_id']}',
      status: '${json['status']}',
      userA: '${json['user_a']}',
      userB: '${json['user_b']}',
      partnerId: '${json['partner_id']}',
      wordLength: asInt(json['word_length']) ?? 0,
      serverObservedAt:
          time(json['server_observed_at']) ?? DateTime.now().toUtc(),
      bothTerminal: json['both_terminal'] == true,
      grid: parseGrid(json['grid']),
      word: json['word'] == null ? null : '${json['word']}',
      myStatus: WordHuntStatus.fromWire(json['my_status'] as String?),
      myStartedAt: time(json['my_started_at']),
      myDeadlineAt: time(json['my_deadline_at']),
      myElapsedMs: asInt(json['my_elapsed_ms']),
      partnerStatus:
          json.containsKey('partner_status')
              ? WordHuntStatus.fromWire(json['partner_status'] as String?)
              : null,
      partnerElapsedMs: asInt(json['partner_elapsed_ms']),
      placement: parsePlacement(json['placement']),
    );
  }
}

/// What one submission came back with.
@immutable
class WordHuntSubmission {
  const WordHuntSubmission({required this.hit, required this.session});

  final bool hit;
  final WordHuntSession session;
}

/// An error the server named, with a message already fit to show.
@immutable
class WordHuntApiError implements Exception {
  const WordHuntApiError({required this.code, required this.message});

  final String code;
  final String message;

  factory WordHuntApiError.fromJson(Map<String, dynamic> json) =>
      WordHuntApiError(
        code: '${json['code'] ?? 'UNKNOWN'}',
        message: '${json['message'] ?? 'Something went wrong.'}',
      );

  /// True when retrying cannot help, so the UI offers a way out rather
  /// than a retry button.
  bool get isTerminal =>
      code == 'SESSION_EXPIRED' || code == 'GAME_OVER' || code == 'NOT_FOUND';

  @override
  String toString() => 'WordHuntApiError($code): $message';
}
