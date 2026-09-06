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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockRealtimeChannel extends Mock implements RealtimeChannel {}

class _ScreenGateway implements PaintBallGateway {
  _ScreenGateway(this.session, this.channel);

  PaintBallSessionState? session;
  PaintBallShotResult? turnResult;
  final RealtimeChannel channel;

  @override
  Future<void> acceptSession(String sessionId) async {}

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
  Future<PaintBallShotResult> takeTurn({
    required String sessionId,
    required int roundNumber,
    required int hidePosition,
    required int shotPosition,
  }) async => turnResult!;
}

PaintBallSessionState _session({
  String status = 'active',
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
  'initiator_id': 'user-a',
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

  testWidgets('battle requires both choices and reveals server verdict', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final gateway = _ScreenGateway(_session(), channel)
      ..turnResult = const PaintBallShotResult(
        sessionId: 'session-1',
        roundNumber: 2,
        shotResult: 'hit',
        lifeLost: true,
        livesA: 3,
        livesB: 2,
        currentTurnUserId: 'user-b',
        knockout: false,
        penaltyType: null,
        penaltySource: null,
        penaltyPromptSnapshot: null,
        existing: false,
        defenderWasAt: 1,
      );

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        child: const PaintBallBattleScreen(sessionId: 'session-1'),
      ),
    );
    await tester.pump();
    await tester.pump();

    AppButton fire() =>
        tester.widget<AppButton>(find.widgetWithText(AppButton, 'Fire'));
    expect(fire().onPressed, isNull);

    await _scrollToEnd(tester);
    await tester.tap(find.text('Left'));
    await tester.tap(find.bySemanticsLabel('Middle target'));
    await tester.pump();
    expect(fire().onPressed, isNotNull);

    await tester.tap(find.widgetWithText(AppButton, 'Fire'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Direct hit'), findsOneWidget);
    expect(
      find.textContaining('They were behind the middle shield.'),
      findsOneWidget,
    );
    expect(find.text('Done for now'), findsOneWidget);
  });

  testWidgets('a fast server verdict waits for projectile impact', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final gateway = _ScreenGateway(_session(), channel)
      ..turnResult = const PaintBallShotResult(
        sessionId: 'session-1',
        roundNumber: 2,
        shotResult: 'hit',
        lifeLost: true,
        livesA: 3,
        livesB: 2,
        currentTurnUserId: 'user-b',
        knockout: false,
        penaltyType: null,
        penaltySource: null,
        penaltyPromptSnapshot: null,
        existing: false,
        defenderWasAt: 1,
      );

    await tester.pumpWidget(
      _wrap(
        gateway: gateway,
        reduceMotion: false,
        child: const PaintBallBattleScreen(sessionId: 'session-1'),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _scrollToEnd(tester);
    await tester.tap(find.text('Left'));
    await tester.tap(find.bySemanticsLabel('Middle target'));
    await tester.pump(const Duration(milliseconds: 250));

    final fireButton = find.widgetWithText(AppButton, 'Fire');
    await tester.ensureVisible(fireButton);
    await tester.pump(const Duration(milliseconds: 100));
    tester.widget<AppButton>(fireButton).onPressed!.call();
    await tester.pump();
    expect(find.text('Paint is in the air.'), findsOneWidget);
    expect(find.text('Direct hit'), findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Direct hit'), findsNothing);

    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Direct hit'), findsOneWidget);
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
}
