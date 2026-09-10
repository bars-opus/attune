import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing is where the disclosure boundary is READ.
///
/// The server withholds by omitting a key entirely rather than sending
/// null, so that a client cannot tell "withheld" from "not yet" by the
/// shape of the response. That only holds if the client treats an absent
/// key as absent -- and nothing tested that until these.
void main() {
  Map<String, dynamic> base({Map<String, dynamic> extra = const {}}) => {
    'session_id': 's1',
    'relationship_id': 'r1',
    'initiator_id': 'u1',
    'status': 'active',
    'user_a': 'u1',
    'user_b': 'u2',
    'partner_id': 'u2',
    'word_length': 5,
    'server_observed_at': '2026-09-08T12:00:30Z',
    'both_terminal': false,
    ...extra,
  };

  List<String> grid() => List.filled(10, 'ABCDEFGHIJ');

  group('the disclosure boundary as the client reads it', () {
    test('no grid, word or placement before Start', () {
      final s = WordHuntSession.fromJson(base());
      expect(s.grid, isNull);
      expect(s.word, isNull);
      expect(s.placement, isNull);
      expect(s.hasStarted, isFalse);
    });

    test('an absent partner_status is null, not a default status', () {
      // If this parsed to inProgress the reveal would render a partner
      // row for someone whose state was deliberately withheld.
      final s = WordHuntSession.fromJson(base());
      expect(s.partnerStatus, isNull);
      expect(s.partnerElapsedMs, isNull);
    });

    test('a present partner_status is read', () {
      final s = WordHuntSession.fromJson(
        base(
          extra: {
            'both_terminal': true,
            'partner_status': 'gave_up',
            'partner_elapsed_ms': null,
          },
        ),
      );
      expect(s.partnerStatus, WordHuntStatus.gaveUp);
      expect(s.bothTerminal, isTrue);
    });

    test('did_not_play survives the wire as its own state', () {
      final s = WordHuntSession.fromJson(
        base(extra: {'both_terminal': true, 'partner_status': 'did_not_play'}),
      );
      expect(s.partnerStatus, WordHuntStatus.didNotPlay);
    });
  });

  group('grid parsing refuses what it cannot draw', () {
    test('accepts exactly ten rows of ten', () {
      final s = WordHuntSession.fromJson(base(extra: {'grid': grid()}));
      expect(s.grid, hasLength(10));
    });

    test('rejects a short grid rather than drawing a partial board', () {
      // Letters at coordinates the server does not agree with would make
      // a correct drag read as wrong.
      final s = WordHuntSession.fromJson(
        base(extra: {'grid': List.filled(9, 'ABCDEFGHIJ')}),
      );
      expect(s.grid, isNull);
    });

    test('rejects a ragged grid', () {
      final rows = grid()..[4] = 'ABC';
      final s = WordHuntSession.fromJson(base(extra: {'grid': rows}));
      expect(s.grid, isNull);
    });

    test('rejects a non-list grid', () {
      final s = WordHuntSession.fromJson(base(extra: {'grid': 'ABCDEFGHIJ'}));
      expect(s.grid, isNull);
    });
  });

  group('placement parsing', () {
    test('reads a well-formed placement', () {
      final s = WordHuntSession.fromJson(
        base(
          extra: {
            'placement': [
              [0, 0],
              [0, 1],
            ],
          },
        ),
      );
      expect(s.placement, const [WordHuntCell(0, 0), WordHuntCell(0, 1)]);
    });

    test('rejects an out-of-bounds cell wholesale', () {
      // Partially trusting it would draw a pill off the board.
      final s = WordHuntSession.fromJson(
        base(
          extra: {
            'placement': [
              [0, 0],
              [0, 99],
            ],
          },
        ),
      );
      expect(s.placement, isNull);
    });

    test('rejects a malformed cell', () {
      final s = WordHuntSession.fromJson(
        base(
          extra: {
            'placement': [
              [0, 0],
              [1],
            ],
          },
        ),
      );
      expect(s.placement, isNull);
    });

    test('an empty placement is null rather than an empty pill', () {
      final s = WordHuntSession.fromJson(base(extra: {'placement': []}));
      expect(s.placement, isNull);
    });
  });

  group('derived state', () {
    test('waiting means terminal for me and not yet for both', () {
      final s = WordHuntSession.fromJson(
        base(
          extra: {
            'my_status': 'found',
            'my_started_at': '2026-09-08T12:00:00Z',
            'my_elapsed_ms': 12000,
          },
        ),
      );
      expect(s.isWaitingForPartner, isTrue);
      expect(s.myStatus.foundIt, isTrue);
    });

    test('not waiting once both are terminal', () {
      final s = WordHuntSession.fromJson(
        base(
          extra: {
            'both_terminal': true,
            'my_status': 'found',
            'my_started_at': '2026-09-08T12:00:00Z',
            'partner_status': 'timed_out',
          },
        ),
      );
      expect(s.isWaitingForPartner, isFalse);
    });

    test('not waiting while still hunting', () {
      final s = WordHuntSession.fromJson(
        base(
          extra: {
            'my_status': 'in_progress',
            'my_started_at': '2026-09-08T12:00:00Z',
          },
        ),
      );
      expect(s.isWaitingForPartner, isFalse);
    });

    test('lifecycle flags read the session status', () {
      expect(
        WordHuntSession.fromJson(base(extra: {'status': 'invited'})).isInvited,
        isTrue,
      );
      expect(
        WordHuntSession.fromJson(base(extra: {'status': 'completed'})).isOver,
        isTrue,
      );
      expect(
        WordHuntSession.fromJson(base(extra: {'status': 'abandoned'})).isOver,
        isTrue,
      );
      expect(
        WordHuntSession.fromJson(base(extra: {'status': 'active'})).isOver,
        isFalse,
      );
    });

    test('an unparseable server clock falls back rather than throwing', () {
      final s = WordHuntSession.fromJson(
        base(extra: {'server_observed_at': 'not a timestamp'}),
      );
      expect(s.serverObservedAt, isNotNull);
    });
  });

  group('status wire mapping', () {
    test('every known status round-trips', () {
      expect(WordHuntStatus.fromWire('found'), WordHuntStatus.found);
      expect(WordHuntStatus.fromWire('gave_up'), WordHuntStatus.gaveUp);
      expect(WordHuntStatus.fromWire('timed_out'), WordHuntStatus.timedOut);
      expect(
        WordHuntStatus.fromWire('did_not_play'),
        WordHuntStatus.didNotPlay,
      );
      expect(WordHuntStatus.fromWire('in_progress'), WordHuntStatus.inProgress);
    });

    test('an unknown status is treated as still playing, never as found', () {
      // The safe default: a status this client does not understand must
      // not open the reveal or claim someone finished.
      expect(
        WordHuntStatus.fromWire('something_new'),
        WordHuntStatus.inProgress,
      );
      expect(WordHuntStatus.fromWire(null), WordHuntStatus.inProgress);
      expect(WordHuntStatus.fromWire('something_new').isTerminal, isFalse);
    });

    test('isTerminal covers every ending', () {
      expect(WordHuntStatus.found.isTerminal, isTrue);
      expect(WordHuntStatus.gaveUp.isTerminal, isTrue);
      expect(WordHuntStatus.timedOut.isTerminal, isTrue);
      expect(WordHuntStatus.didNotPlay.isTerminal, isTrue);
      expect(WordHuntStatus.inProgress.isTerminal, isFalse);
    });
  });

  group('errors', () {
    test('carries the server message, which is already fit to show', () {
      final e = WordHuntApiError.fromJson({
        'code': 'RATE_LIMITED',
        'message': 'Slow down a moment.',
      });
      expect(e.code, 'RATE_LIMITED');
      expect(e.message, 'Slow down a moment.');
      expect(e.isTerminal, isFalse);
    });

    test('terminal codes are the ones a retry cannot help', () {
      for (final code in ['SESSION_EXPIRED', 'GAME_OVER', 'NOT_FOUND']) {
        expect(
          WordHuntApiError.fromJson({'code': code}).isTerminal,
          isTrue,
          reason: '$code should offer a way out, not a retry',
        );
      }
      expect(
        WordHuntApiError.fromJson({'code': 'RATE_LIMITED'}).isTerminal,
        isFalse,
      );
    });

    test('a malformed error still produces something showable', () {
      final e = WordHuntApiError.fromJson({});
      expect(e.code, 'UNKNOWN');
      expect(e.message, isNotEmpty);
    });
  });

  test('cells compare by value, which the drag path relies on', () {
    expect(const WordHuntCell(2, 3), const WordHuntCell(2, 3));
    expect(const WordHuntCell(2, 3), isNot(const WordHuntCell(3, 2)));
    expect({const WordHuntCell(1, 1), const WordHuntCell(1, 1)}, hasLength(1));
    expect(const WordHuntCell(9, 9).inBounds, isTrue);
    expect(const WordHuntCell(10, 0).inBounds, isFalse);
    expect(const WordHuntCell(-1, 0).inBounds, isFalse);
  });
}
