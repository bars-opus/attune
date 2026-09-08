import 'dart:async';

import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/presentation/state/word_hunt_provider.dart';
import 'package:attune/features/games/word_hunt/services/word_hunt_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A gateway that answers from a script, so the notifier's own decisions
/// -- what to keep, what to clear, what never to say -- are the only
/// thing under test.
class _FakeGateway implements WordHuntGateway {
  _FakeGateway(this.state);

  WordHuntSession state;
  bool nextHit = false;
  WordHuntApiError? throwOnSubmit;
  int submitCount = 0;
  List<WordHuntCell>? lastCells;

  /// Lets a test hold a getState call open, so a stale response can be
  /// made to land AFTER a newer write — the ordering that made the
  /// reveal disappear in review.
  Completer<WordHuntSession>? gateState;

  @override
  Future<String> createSession({
    required String relationshipId,
    required String idempotencyKey,
  }) async => 's1';

  @override
  Future<void> acceptSession(String sessionId) async {}

  @override
  Future<void> declineSession(String sessionId) async {}

  @override
  Future<WordHuntSession> start(String sessionId) async => state;

  @override
  Future<WordHuntSubmission> submit({
    required String sessionId,
    required List<WordHuntCell> cells,
  }) async {
    submitCount++;
    lastCells = cells;
    final error = throwOnSubmit;
    if (error != null) throw error;
    return WordHuntSubmission(hit: nextHit, session: state);
  }

  @override
  Future<WordHuntSession> giveUp(String sessionId) async => state;

  @override
  Future<WordHuntSession> getState(String sessionId) {
    final gate = gateState;
    if (gate != null) return gate.future;
    return Future.value(state);
  }

  @override
  Future<WordHuntSession?> getActiveSession(String relationshipId) async =>
      state;
}

WordHuntSession session({
  String status = 'active',
  String myStatus = 'in_progress',
  DateTime? startedAt,
  DateTime? observedAt,
  int? elapsedMs,
  bool bothTerminal = false,
}) => WordHuntSession.fromJson({
  'session_id': 's1',
  'relationship_id': 'r1',
  'initiator_id': 'u1',
  'status': status,
  'user_a': 'u1',
  'user_b': 'u2',
  'partner_id': 'u2',
  'word_length': 4,
  'server_observed_at':
      (observedAt ?? DateTime.utc(2026, 9, 8, 12, 0, 30)).toIso8601String(),
  'both_terminal': bothTerminal,
  'my_status': myStatus,
  if (startedAt != null) 'my_started_at': startedAt.toIso8601String(),
  if (elapsedMs != null) 'my_elapsed_ms': elapsedMs,
  'grid': List.filled(10, 'ABCDEFGHIJ'),
  'word': 'LOVE',
});

void main() {
  ProviderContainer host(_FakeGateway gateway) => ProviderContainer(
    overrides: [wordHuntGatewayProvider.overrideWithValue(gateway)],
  );

  group('the display clock', () {
    test('seeds from the server pair, not the device clock', () async {
      // 30 seconds between started_at and server_observed_at, so the
      // display starts at 30s however wrong the device's clock is.
      final gateway = _FakeGateway(
        session(
          startedAt: DateTime.utc(2026, 9, 8, 12, 0, 0),
          observedAt: DateTime.utc(2026, 9, 8, 12, 0, 30),
        ),
      );
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.displayElapsed.inSeconds, greaterThanOrEqualTo(30));
      expect(notifier.displayElapsed.inSeconds, lessThan(32));
    });

    test(
      'a terminal attempt stops the clock rather than drifting on',
      () async {
        final gateway = _FakeGateway(
          session(
            myStatus: 'found',
            startedAt: DateTime.utc(2026, 9, 8, 12, 0, 0),
            observedAt: DateTime.utc(2026, 9, 8, 12, 0, 30),
            elapsedMs: 30000,
          ),
        );
        final container = host(gateway);
        addTearDown(container.dispose);

        final notifier = container.read(wordHuntProvider('s1').notifier);
        await Future<void>.delayed(Duration.zero);

        expect(notifier.displayElapsed, Duration.zero);
      },
    );

    test('a server_observed_at before started_at clamps to zero', () async {
      // Clock skew must not produce a negative running time.
      final gateway = _FakeGateway(
        session(
          startedAt: DateTime.utc(2026, 9, 8, 12, 0, 30),
          observedAt: DateTime.utc(2026, 9, 8, 12, 0, 0),
        ),
      );
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.displayElapsed.isNegative, isFalse);
    });
  });

  group('submitting', () {
    test('a miss is recorded for the board, with no error shown', () async {
      final gateway = _FakeGateway(
        session(startedAt: DateTime.utc(2026, 9, 8, 12)),
      )..nextHit = false;
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);
      await notifier.submit(const [WordHuntCell(0, 0), WordHuntCell(0, 1)]);

      final state = container.read(wordHuntProvider('s1'));
      // A wrong guess costs nothing and SAYS nothing: the pill animates
      // off and that is the whole feedback.
      expect(state.errorMessage, isNull);
      expect(state.missCells, hasLength(2));
      expect(state.missNonce, 1);
    });

    test('the same wrong guess twice animates twice', () async {
      final gateway = _FakeGateway(
        session(startedAt: DateTime.utc(2026, 9, 8, 12)),
      )..nextHit = false;
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);
      const cells = [WordHuntCell(0, 0), WordHuntCell(0, 1)];
      await notifier.submit(cells);
      await notifier.submit(cells);

      // The nonce is why: identical cells would otherwise look unchanged
      // and the second dismissal would never play.
      expect(container.read(wordHuntProvider('s1')).missNonce, 2);
    });

    test('a hit clears the miss rather than leaving a stale pill', () async {
      final gateway = _FakeGateway(
        session(startedAt: DateTime.utc(2026, 9, 8, 12)),
      )..nextHit = false;
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);
      await notifier.submit(const [WordHuntCell(0, 0), WordHuntCell(0, 1)]);
      gateway.nextHit = true;
      await notifier.submit(const [WordHuntCell(1, 0), WordHuntCell(1, 1)]);

      expect(container.read(wordHuntProvider('s1')).missCells, isNull);
    });

    test('the rate limiter is silent, not an error banner', () async {
      // It fires on a double-submit from one drag. A red banner for that
      // is noise mid-hunt.
      final gateway = _FakeGateway(
          session(startedAt: DateTime.utc(2026, 9, 8, 12)),
        )
        ..throwOnSubmit = const WordHuntApiError(
          code: 'RATE_LIMITED',
          message: 'Slow down a moment.',
        );
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);
      await notifier.submit(const [WordHuntCell(0, 0), WordHuntCell(0, 1)]);

      final state = container.read(wordHuntProvider('s1'));
      expect(state.errorMessage, isNull);
      expect(state.missNonce, 1);
    });

    test('any other server error IS shown', () async {
      final gateway = _FakeGateway(
          session(startedAt: DateTime.utc(2026, 9, 8, 12)),
        )
        ..throwOnSubmit = const WordHuntApiError(
          code: 'SESSION_EXPIRED',
          message: 'This session expired. Start a new game.',
        );
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);
      await notifier.submit(const [WordHuntCell(0, 0), WordHuntCell(0, 1)]);

      expect(
        container.read(wordHuntProvider('s1')).errorMessage,
        'This session expired. Start a new game.',
      );
    });

    test('a second submit is refused while one is in flight', () async {
      // Two drags racing would let the later one report against the
      // earlier one's state.
      final gateway = _FakeGateway(
        session(startedAt: DateTime.utc(2026, 9, 8, 12)),
      );
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);

      final first = notifier.submit(const [WordHuntCell(0, 0)]);
      final second = notifier.submit(const [WordHuntCell(1, 1)]);
      await Future.wait([first, second]);

      expect(gateway.submitCount, 1);
    });

    test('the cells reach the gateway unchanged and in order', () async {
      final gateway = _FakeGateway(
        session(startedAt: DateTime.utc(2026, 9, 8, 12)),
      );
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);
      const cells = [
        WordHuntCell(3, 1),
        WordHuntCell(3, 2),
        WordHuntCell(3, 3),
      ];
      await notifier.submit(cells);

      // The server compares an ORDERED path, so a reordering here would
      // turn a correct drag into a miss.
      expect(gateway.lastCells, cells);
    });
  });

  test(
    'a load failure leaves a message rather than an endless spinner',
    () async {
      final gateway = _FakeGateway(session());
      final container = host(gateway);
      addTearDown(container.dispose);
      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(wordHuntProvider('s1')).isLoading, isFalse);
    },
  );

  group('a stale response cannot undo a newer one', () {
    // FOUND IN REVIEW. refresh() runs from construction, from lifecycle
    // resume, and from every realtime event, so several are in flight at
    // once and return in whatever order the network decides. Without
    // sequencing: refresh A reads an in-progress snapshot and stalls,
    // submit installs the terminal reveal, then refresh A returns and
    // overwrites it — the reveal vanishes and the player is back on a
    // grid whose clock has already stopped.
    test('a slow refresh does not overwrite a finished submit', () async {
      final playing = session(startedAt: DateTime.utc(2026, 9, 8, 12));
      final gateway = _FakeGateway(playing)..nextHit = true;
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);

      // A refresh starts and is held open, carrying the in-progress view.
      final gate = Completer<WordHuntSession>();
      gateway.gateState = gate;
      final slow = notifier.refresh();

      // The submit lands first and finishes the attempt.
      gateway.gateState = null;
      gateway.state = session(
        myStatus: 'found',
        startedAt: DateTime.utc(2026, 9, 8, 12),
        elapsedMs: 30000,
        bothTerminal: true,
      );
      await notifier.submit(const [WordHuntCell(0, 0), WordHuntCell(0, 1)]);
      expect(
        container.read(wordHuntProvider('s1')).session!.myStatus,
        WordHuntStatus.found,
      );

      // Now the stale refresh returns with the OLD in-progress snapshot.
      gate.complete(playing);
      await slow;

      expect(
        container.read(wordHuntProvider('s1')).session!.myStatus,
        WordHuntStatus.found,
        reason: 'a stale refresh reopened a finished attempt',
      );
      expect(
        container.read(wordHuntProvider('s1')).session!.bothTerminal,
        isTrue,
        reason: 'a stale refresh closed the reveal',
      );
    });

    test('a stale refresh cannot reopen a completed session', () async {
      final open = session(
        status: 'active',
        startedAt: DateTime.utc(2026, 9, 8, 12),
      );
      final gateway = _FakeGateway(open);
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);

      final gate = Completer<WordHuntSession>();
      gateway.gateState = gate;
      final slow = notifier.refresh();

      gateway.gateState = null;
      gateway.state = session(
        status: 'completed',
        myStatus: 'gave_up',
        startedAt: DateTime.utc(2026, 9, 8, 12),
        bothTerminal: true,
      );
      await notifier.giveUp();
      expect(container.read(wordHuntProvider('s1')).session!.isOver, isTrue);

      gate.complete(open);
      await slow;

      expect(
        container.read(wordHuntProvider('s1')).session!.isOver,
        isTrue,
        reason: 'a stale refresh reopened a completed session',
      );
    });

    test('a fresher refresh still installs normally', () async {
      // The guard must not freeze the screen: ordinary forward progress
      // has to keep working, or a waiting player never sees the reveal.
      final gateway = _FakeGateway(
        session(startedAt: DateTime.utc(2026, 9, 8, 12)),
      );
      final container = host(gateway);
      addTearDown(container.dispose);

      final notifier = container.read(wordHuntProvider('s1').notifier);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(wordHuntProvider('s1')).session!.bothTerminal,
        isFalse,
      );

      gateway.state = session(
        status: 'completed',
        myStatus: 'found',
        startedAt: DateTime.utc(2026, 9, 8, 12),
        elapsedMs: 9000,
        bothTerminal: true,
      );
      await notifier.refresh();

      expect(
        container.read(wordHuntProvider('s1')).session!.bothTerminal,
        isTrue,
        reason: 'the guard blocked legitimate forward progress',
      );
    });
  });
}
