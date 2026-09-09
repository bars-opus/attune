import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/features/games/paint_ball/analytics/paint_ball_analytics.dart';
import 'package:attune/features/games/paint_ball/models/paint_ball_models.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_battle_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_knockout_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_lobby_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/state/paint_ball_provider.dart';
import 'package:attune/features/games/paint_ball/services/paint_ball_service.dart';
import 'package:attune/features/games/presentation/widgets/round_handoff.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockRealtimeChannel extends Mock implements RealtimeChannel {}

class _ScreenGateway implements PaintBallGateway {
  _ScreenGateway(this.session, this.channel);

  PaintBallSessionState? session;
  PaintBallTurnResult? turnResult;
  int turnCalls = 0;
  final RealtimeChannel channel;

  int acceptCalls = 0;

  @override
  Future<void> acceptSession(String sessionId) async => acceptCalls++;

  @override
  Future<PaintBallCreateSessionResponse> createSession({
    required String relationshipId,
    String tone = 'playful',
    String? idempotencyKey,
    bool allowPartnerAuthored = false,
  }) async => const PaintBallCreateSessionResponse(
    sessionId: 'session-1',
    existing: false,
  );

  @override
  Future<void> declineSession(String sessionId) async {}

  @override
  Future<PaintBallSessionState?> getActiveSession(
    String relationshipId,
  ) async => session;

  @override
  Future<PaintBallHistoryPage> getHistory({
    required String relationshipId,
    int limit = 20,
    String? cursor,
  }) async => const PaintBallHistoryPage(items: [], nextCursor: null);

  @override
  Future<PaintBallSessionState> getSessionState(String sessionId) async =>
      session!;

  @override
  Future<void> hideSession(String sessionId) async {}

  @override
  Future<void> resolvePenalty({
    required String sessionId,
    required String outcome,
  }) async {
    session = session!.copyWith(
      status: 'completed',
      penaltyStatus: outcome,
      completedAt: DateTime.utc(2026, 9, 6),
    );
  }

  @override
  RealtimeChannel subscribeToSession(
    String sessionId, {
    required void Function(Map<String, dynamic> payload) onUpdate,
  }) => channel;

  @override
  Future<PaintBallTurnResult> takeTurn({
    required String sessionId,
    required int roundNumber,
    required int hidePosition,
    required int shotPosition,
  }) async {
    turnCalls++;
    return turnResult!;
  }
}

PaintBallSessionState _session({
  String status = 'active',
  String initiatorId = 'user-a',
  String? currentTurnUserId = 'user-a',
  int currentRound = 2,
  int livesA = 3,
  int livesB = 3,
  String? winnerUserId,
  String? penaltyStatus,
  String? prompt,
}) => PaintBallSessionState.fromJson({
  'session_id': 'session-1',
  'relationship_id': 'relationship-1',
  'initiator_id': initiatorId,
  'user_a_id': 'user-a',
  'user_b_id': 'user-b',
  'status': status,
  'game_type': 'paint_ball',
  'tone': 'playful',
  'current_round': currentRound,
  'total_rounds_completed': currentRound - 1,
  'current_turn_user_id': currentTurnUserId,
  'lives_a': livesA,
  'lives_b': livesB,
  'winner_user_id': winnerUserId,
  'penalty_type': winnerUserId == null ? null : 'truth',
  'penalty_status': penaltyStatus,
  'penalty_source': winnerUserId == null ? null : 'app_random',
  'penalty_prompt_snapshot': prompt,
  'rounds': const <Map<String, dynamic>>[],
});

Widget _wrap({
  required Widget child,
  required PaintBallGateway gateway,
  bool reduceMotion = true,
}) => ProviderScope(
  overrides: [
    paintBallServiceProvider.overrideWithValue(gateway),
    paintBallCurrentUserIdProvider.overrideWithValue('user-a'),
    soundServiceProvider.overrideWithValue(FakeSoundService()),
    hapticsProvider.overrideWithValue(FakeHaptics()),
    paintBallAnalyticsProvider.overrideWithValue(const PaintBallAnalytics()),
  ],
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder:
        (context, _) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              disableAnimations: reduceMotion,
            ),
            child: child,
          ),
        ),
  ),
);

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pump();
}

void main() {
  late _MockRealtimeChannel channel;

  setUp(() {
    channel = _MockRealtimeChannel();
    when(() => channel.unsubscribe()).thenAnswer((_) async => 'ok');
  });

  testWidgets('lobby explains the relationship read, choices, and lives', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final gateway = _ScreenGateway(null, channel);

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        child: const PaintBallLobbyScreen(relationshipId: 'relationship-1'),
      ),
    );
    await tester.pump();

    expect(
      find.text('A quick read on the person you know best'),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -340));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Lives'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Choices'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Start game'), findsOneWidget);
  });

  testWidgets('an invitation from the partner is accepted by the tap', (
    tester,
  ) async {
    // Tapping their card IS the acceptance. Asking again on a screen of
    // its own made the partner confirm the thing they had just done --
    // and the game cannot leave the invited state until someone says
    // yes, so this says it.
    _usePhoneViewport(tester);
    final gateway = _ScreenGateway(
      _session(status: 'invited', initiatorId: 'user-b'),
      channel,
    );

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        child: const PaintBallLobbyScreen(relationshipId: 'relationship-1'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(gateway.acceptCalls, 1);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
  });

  testWidgets('an invitation you sent offers to cancel, not to go back', (
    tester,
  ) async {
    // "Back to chat" was a button whose only job was to leave a screen
    // with nothing to say. Cancelling is the useful thing here; the
    // system back gesture already covers the other.
    _usePhoneViewport(tester);
    final gateway = _ScreenGateway(
      _session(status: 'invited', initiatorId: 'user-a'),
      channel,
    );

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        child: const PaintBallLobbyScreen(relationshipId: 'relationship-1'),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _scrollToEnd(tester);

    expect(gateway.acceptCalls, 0);
    expect(find.text('Cancel invitation'), findsOneWidget);
    expect(find.text('Back to chat'), findsNothing);
  });

  testWidgets('battle requires both choices and reveals server verdict', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final gateway = _ScreenGateway(_session(), channel)
      ..turnResult = const PaintBallTurnResult(
        roundNumber: 2,
        livesA: 3,
        livesB: 2,
        currentTurnUserId: 'user-b',
        knockout: false,
        doubleKnockout: false,
        opener: PaintBallHalf(
          userId: 'user-a',
          hidePosition: 0,
          shotPosition: 1,
          shotResult: 'hit',
        ),
        closer: PaintBallHalf(
          userId: 'user-b',
          hidePosition: 1,
          shotPosition: 2,
          shotResult: 'miss',
        ),
      );

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        child: const PaintBallBattleScreen(sessionId: 'session-1'),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The board is the whole controller: no Fire button exists to
    // duplicate what tapping your own character already does.
    expect(find.widgetWithText(AppButton, 'Fire'), findsNothing);

    await _scrollToEnd(tester);
    await tester.tap(find.bySemanticsLabel('Left cover'));
    await tester.tap(find.bySemanticsLabel('Middle target'));
    await tester.pump();

    await tester.tap(
      find
          .descendant(
            of: find.bySemanticsLabel('Left cover'),
            matching: find.byType(CustomPaint),
          )
          .first,
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump();

    // The round resolves silently. No verdict text, no position readout,
    // no dismiss button -- the field showed what happened, and narrating
    // it underneath would hand out a read the player should earn by
    // watching.
    expect(find.text('Direct hit'), findsNothing);
    expect(find.textContaining('They were behind'), findsNothing);
    expect(find.text('Done for now'), findsNothing);

    // The turn has passed, so the hold before the hand-off to the chat
    // is now running. Let it finish rather than leaving a live timer.
    await tester.pump(kRoundHandoffDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('loser sees one prompt and can always skip freely', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    const prompt = 'Name one tiny thing that would feel caring this week.';
    final gateway = _ScreenGateway(
      _session(
        currentTurnUserId: null,
        livesA: 0,
        winnerUserId: 'user-b',
        penaltyStatus: 'pending',
        prompt: prompt,
      ),
      channel,
    );

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        child: const PaintBallKnockoutScreen(sessionId: 'session-1'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(prompt), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Skip this one'), findsOneWidget);

    await _scrollToEnd(tester);
    await tester.tap(find.text('Skip this one'));
    await tester.pump();

    expect(find.text('Nice read.'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    expect(
      find.textContaining('does not keep a running score'),
      findsOneWidget,
    );
  });

  testWidgets('winner waits without seeing the loser prompt', (tester) async {
    _usePhoneViewport(tester);
    const prompt = 'This content belongs only to the losing partner.';
    final gateway = _ScreenGateway(
      _session(
        currentTurnUserId: null,
        livesB: 0,
        winnerUserId: 'user-a',
        penaltyStatus: 'pending',
        prompt: prompt,
      ),
      channel,
    );

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        child: const PaintBallKnockoutScreen(sessionId: 'session-1'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('You read them right.'), findsOneWidget);
    expect(find.text(prompt), findsNothing);
    expect(find.text('Waiting for them to wrap up'), findsOneWidget);
  });

  testWidgets('a finished round says nothing at all', (tester) async {
    // The field showed what happened. Narrating it underneath hands the
    // player a read they should have earned by watching, and turns a
    // duel between two people into a match report.
    _usePhoneViewport(tester);
    final gateway = _ScreenGateway(_session(), channel)
      ..turnResult = const PaintBallTurnResult(
        roundNumber: 2,
        livesA: 3,
        livesB: 2,
        currentTurnUserId: 'user-a',
        knockout: false,
        doubleKnockout: false,
        opener: PaintBallHalf(
          userId: 'user-a',
          hidePosition: 0,
          shotPosition: 1,
          shotResult: 'hit',
        ),
        closer: PaintBallHalf(
          userId: 'user-b',
          hidePosition: 1,
          shotPosition: 2,
          shotResult: 'miss',
        ),
      );

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        child: const PaintBallBattleScreen(sessionId: 'session-1'),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _scrollToEnd(tester);

    await tester.tap(find.bySemanticsLabel('Left cover'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.bySemanticsLabel('Middle target'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find
          .descendant(
            of: find.bySemanticsLabel('Left cover'),
            matching: find.byType(CustomPaint),
          )
          .first,
      warnIfMissed: false,
    );
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (final commentary in [
      'Direct hit',
      'A useful miss',
      'Both missed',
      'You got each other',
      'They read you',
      'Done for now',
      'Opening move set',
    ]) {
      expect(
        find.text(commentary),
        findsNothing,
        reason: 'the board speaks for itself; "$commentary" does not',
      );
    }
    expect(find.textContaining('They were behind'), findsNothing);
  });

  testWidgets('the screen holds the result, then leaves on its own', (
    tester,
  ) async {
    // Your move is in and the round is with your partner. It used to pop
    // on the spot, which swallowed the thing the player came for: where
    // the shot landed and what it cost. The board is held long enough to
    // read, then the game returns to the chat by itself -- never parking
    // the player behind a dismiss button.
    _usePhoneViewport(tester);
    final gateway = _ScreenGateway(
      _session(currentTurnUserId: 'user-b'),
      channel,
    );

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        child: const PaintBallBattleScreen(sessionId: 'session-1'),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Still there: the result has not been swallowed.
    expect(find.byType(RoundHandoff), findsOneWidget);
    expect(
      find.text('Back to chat'),
      findsNothing,
      reason: 'nothing to dismiss -- the screen dismisses itself',
    );
    expect(
      find.text('Your move is saved. Waiting for theirs.'),
      findsNothing,
      reason: 'no waiting copy on a screen that is leaving',
    );

    // And then it goes, without anyone pressing anything.
    await tester.pump(kRoundHandoffDuration);
    await tester.pumpAndSettle();
    expect(find.byType(PaintBallBattleScreen), findsNothing);
  });

  testWidgets('past rounds leave no paint on the board', (tester) async {
    // A match of several rounds must not accumulate splats. Every past
    // shot painted on the field is a record of where your partner fires
    // -- a free read of their habits, which is the one thing this game
    // asks you to work out yourself.
    _usePhoneViewport(tester);
    final gateway = _ScreenGateway(
      _session(currentRound: 4).copyWith(
        rounds: [
          for (var round = 1; round <= 3; round++)
            PaintBallRound(
              roundNumber: round,
              shotResult: 'miss',
              lifeLost: false,
              createdAt: DateTime.now(),
              activePartnerId: round.isEven ? 'user-a' : 'user-b',
              shotPosition: round % 3,
              hidePosition: round % 3,
            ),
        ],
      ),
      channel,
    );

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        child: const PaintBallBattleScreen(sessionId: 'session-1'),
      ),
    );
    await tester.pump();
    await tester.pump();

    final field = tester.widget<PaintBallField>(find.byType(PaintBallField));
    expect(
      field.splats,
      isEmpty,
      reason: 'three resolved rounds left no trail behind them',
    );
  });
}
