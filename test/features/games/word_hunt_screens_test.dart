import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/presentation/screens/word_hunt_game_screen.dart';
import 'package:attune/features/games/word_hunt/presentation/state/word_hunt_provider.dart';
import 'package:attune/features/games/word_hunt/presentation/widgets/word_hunt_board.dart';
import 'package:attune/features/games/word_hunt/services/word_hunt_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// What each state of the hunt actually puts on screen.
///
/// The states matter more than usual here because three of them exist to
/// WITHHOLD something: before Start there is no grid, while waiting there
/// is nothing of the partner's, and only at the end is there a result.
/// A screen that renders the wrong one leaks the thing the whole server
/// contract was built to hold back.
class _ScriptedGateway implements WordHuntGateway {
  _ScriptedGateway(this.state);

  WordHuntSession? state;
  WordHuntApiError? failWith;
  int startCalls = 0;
  int giveUpCalls = 0;

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
  Future<WordHuntSession> start(String sessionId) async {
    startCalls++;
    final error = failWith;
    if (error != null) throw error;
    return state!;
  }

  @override
  Future<WordHuntSubmission> submit({
    required String sessionId,
    required List<WordHuntCell> cells,
  }) async => WordHuntSubmission(hit: false, session: state!);

  @override
  Future<WordHuntSession> giveUp(String sessionId) async {
    giveUpCalls++;
    return state!;
  }

  @override
  Future<WordHuntSession> getState(String sessionId) async {
    final error = failWith;
    if (error != null) throw error;
    return state!;
  }

  @override
  Future<WordHuntSession?> getActiveSession(String relationshipId) async =>
      state;
}

WordHuntSession session({
  String status = 'active',
  String myStatus = 'in_progress',
  bool started = false,
  bool bothTerminal = false,
  String? partnerStatus,
  int? myElapsedMs,
  int? partnerElapsedMs,
  bool withGrid = true,
}) => WordHuntSession.fromJson({
  'session_id': 's1',
  'relationship_id': 'r1',
  'initiator_id': 'u1',
  'status': status,
  'user_a': 'u1',
  'user_b': 'u2',
  'partner_id': 'u2',
  'word_length': 4,
  'server_observed_at': '2026-09-08T12:00:30Z',
  'both_terminal': bothTerminal,
  'my_status': myStatus,
  if (started) 'my_started_at': '2026-09-08T12:00:00Z',
  if (started && withGrid) 'grid': List.filled(10, 'LOVEABCDEF'),
  if (started && withGrid) 'word': 'LOVE',
  if (myElapsedMs != null) 'my_elapsed_ms': myElapsedMs,
  if (partnerStatus != null) 'partner_status': partnerStatus,
  if (partnerElapsedMs != null) 'partner_elapsed_ms': partnerElapsedMs,
  if (bothTerminal)
    'placement': [
      [0, 0],
      [0, 1],
      [0, 2],
      [0, 3],
    ],
});

void main() {
  Future<void> show(WidgetTester tester, _ScriptedGateway gateway) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [wordHuntGatewayProvider.overrideWithValue(gateway)],
        child: const MaterialApp(
          home: WordHuntGameScreen(relationshipId: 'r1', sessionId: 's1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('before Start: an explanation and a button, never the grid', (
    tester,
  ) async {
    final gateway = _ScriptedGateway(session(started: false));
    await show(tester, gateway);

    expect(find.text('Start'), findsOneWidget);
    expect(find.byType(WordHuntBoard), findsNothing);
    // The clock is named plainly, because tapping Start is what begins it.
    expect(find.textContaining('begins your clock'), findsOneWidget);
    // And the word length is said without saying the word.
    expect(find.textContaining('4-letter word'), findsOneWidget);
    expect(find.text('LOVE'), findsNothing);
  });

  testWidgets('tapping Start asks the server rather than starting locally', (
    tester,
  ) async {
    final gateway = _ScriptedGateway(session(started: false));
    await show(tester, gateway);

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();

    expect(gateway.startCalls, 1);
  });

  testWidgets('after Start: the grid, the word and a running number', (
    tester,
  ) async {
    final gateway = _ScriptedGateway(session(started: true));
    await show(tester, gateway);

    expect(find.byType(WordHuntBoard), findsOneWidget);
    expect(find.text('LOVE'), findsOneWidget);
    expect(find.text('FIND'), findsOneWidget);
    // Nothing else. No partner, no score, no prompt.
    expect(find.textContaining('Them'), findsNothing);
  });

  testWidgets('the give-up affordance is offered while hunting', (
    tester,
  ) async {
    await show(tester, _ScriptedGateway(session(started: true)));
    expect(find.text("Can't find it"), findsOneWidget);
  });

  testWidgets('the give-up affordance is absent before Start', (
    tester,
  ) async {
    // Separate test, not a second pump in the one above: the provider is
    // keyed by session id, so re-pumping in the same test reuses the
    // first notifier and its state rather than building a new one.
    await show(tester, _ScriptedGateway(session(started: false)));
    expect(find.text("Can't find it"), findsNothing);
  });

  testWidgets('the give-up affordance is absent once the attempt is over', (
    tester,
  ) async {
    await show(
      tester,
      _ScriptedGateway(
        session(started: true, myStatus: 'found', myElapsedMs: 9000),
      ),
    );
    expect(find.text("Can't find it"), findsNothing);
  });

  testWidgets('giving up asks first, and only then tells the server', (
    tester,
  ) async {
    final gateway = _ScriptedGateway(session(started: true));
    await show(tester, gateway);

    await tester.tap(find.text("Can't find it"));
    await tester.pumpAndSettle();

    // The dialog says the cost, which is nothing.
    expect(find.textContaining('Nothing is scored'), findsOneWidget);
    expect(gateway.giveUpCalls, 0);

    await tester.tap(find.text('Keep looking'));
    await tester.pumpAndSettle();
    expect(gateway.giveUpCalls, 0);
  });

  testWidgets('waiting: my own time, and nothing at all of theirs', (
    tester,
  ) async {
    // This is the disclosure boundary as the player sees it. One finished
    // attempt must not show the other's time, or the second player starts
    // knowing the number to beat.
    final gateway = _ScriptedGateway(
      session(
        started: true,
        myStatus: 'found',
        myElapsedMs: 12400,
      ),
    );
    await show(tester, gateway);

    expect(find.text('You found it.'), findsOneWidget);
    expect(find.text('12.4s'), findsOneWidget);
    expect(find.textContaining('once they finish'), findsOneWidget);
    expect(find.byType(WordHuntBoard), findsNothing);
  });

  testWidgets('waiting after giving up says so without calling it quitting', (
    tester,
  ) async {
    final gateway = _ScriptedGateway(
      session(started: true, myStatus: 'gave_up'),
    );
    await show(tester, gateway);

    expect(find.text("You didn't find it."), findsOneWidget);
    expect(find.textContaining('gave up'), findsNothing);
    expect(find.textContaining('quit'), findsNothing);
  });

  testWidgets('both terminal: the reveal, with the board back', (
    tester,
  ) async {
    final gateway = _ScriptedGateway(
      session(
        started: true,
        myStatus: 'found',
        myElapsedMs: 12000,
        bothTerminal: true,
        partnerStatus: 'found',
        partnerElapsedMs: 30000,
        status: 'completed',
      ),
    );
    await show(tester, gateway);

    // Not "You were quicker" — a review pointed out that a comparative
    // is a winner declaration in a politer register, and this game has
    // no winner.
    expect(find.text('You both found it'), findsOneWidget);
    expect(find.textContaining('quicker'), findsNothing);
    expect(find.text('Play again'), findsOneWidget);
    // The board comes back so both players see WHERE it was.
    expect(find.byType(WordHuntBoard), findsOneWidget);
  });

  testWidgets('a load failure offers a way out, not an endless spinner', (
    tester,
  ) async {
    final gateway = _ScriptedGateway(null)
      ..failWith = const WordHuntApiError(
        code: 'NOT_FOUND',
        message: 'Game session not found.',
      );
    await show(tester, gateway);

    expect(find.text('Game session not found.'), findsOneWidget);
    expect(find.text('Back to chat'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a grid that failed to parse says so rather than drawing junk', (
    tester,
  ) async {
    final gateway = _ScriptedGateway(
      session(started: true, withGrid: false),
    );
    await show(tester, gateway);

    expect(find.textContaining('did not load'), findsOneWidget);
    expect(find.byType(WordHuntBoard), findsNothing);
  });

  testWidgets('no internal detail reaches the screen', (tester) async {
    // Checklist 5.5: error codes, ids and schema names are not for players.
    final gateway = _ScriptedGateway(null)
      ..failWith = const WordHuntApiError(
        code: 'SESSION_EXPIRED',
        message: 'This session expired. Start a new game.',
      );
    await show(tester, gateway);

    for (final leak in [
      'SESSION_EXPIRED',
      'word_hunt_puzzles',
      'word_hunt_attempts',
      's1',
      'r1',
    ]) {
      expect(
        find.textContaining(leak),
        findsNothing,
        reason: '"$leak" is internal and must not reach the player',
      );
    }
  });
}
