import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/paint_ball/analytics/paint_ball_analytics.dart';
import 'package:attune/features/games/paint_ball/models/paint_ball_models.dart';
import 'package:attune/features/games/paint_ball/presentation/state/paint_ball_provider.dart';
import 'package:attune/features/games/paint_ball/services/paint_ball_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockRealtimeChannel extends Mock implements RealtimeChannel {}

class _TurnCall {
  const _TurnCall(this.sessionId, this.round, this.hide, this.shot);

  final String sessionId;
  final int round;
  final int hide;
  final int shot;
}

class _FakePaintBallGateway implements PaintBallGateway {
  _FakePaintBallGateway(this.session, this.channel);

  PaintBallSessionState? session;
  PaintBallTurnResult? nextResult;
  Object? turnError;
  final RealtimeChannel channel;
  final turnCalls = <_TurnCall>[];
  final penaltyOutcomes = <String>[];

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
    penaltyOutcomes.add(outcome);
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
    turnCalls.add(
      _TurnCall(sessionId, roundNumber, hidePosition, shotPosition),
    );
    if (turnError case final error?) throw error;
    return nextResult!;
  }
}

PaintBallSessionState _session({
  String status = 'active',
  int currentRound = 2,
  String? turnUserId = 'user-a',
  int livesA = 3,
  int livesB = 3,
  String? winnerUserId,
  String? penaltyStatus,
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
  'current_turn_user_id': turnUserId,
  'lives_a': livesA,
  'lives_b': livesB,
  'winner_user_id': winnerUserId,
  'penalty_type': winnerUserId == null ? null : 'truth',
  'penalty_status': penaltyStatus,
  'penalty_prompt_snapshot':
      winnerUserId == null ? null : 'Share one small hope for this week.',
  'is_my_turn': turnUserId == 'user-a',
  'is_winner': winnerUserId == 'user-a',
  'is_loser': winnerUserId != null && winnerUserId != 'user-a',
  'rounds': const <Map<String, dynamic>>[],
});

ProviderContainer _container({
  required _FakePaintBallGateway gateway,
  required FakeSoundService sound,
  required FakeHaptics haptics,
  required PaintBallAnalytics analytics,
}) => ProviderContainer(
  overrides: [
    paintBallServiceProvider.overrideWithValue(gateway),
    paintBallCurrentUserIdProvider.overrideWithValue('user-a'),
    soundServiceProvider.overrideWithValue(sound),
    hapticsProvider.overrideWithValue(haptics),
    paintBallAnalyticsProvider.overrideWithValue(analytics),
  ],
);

void main() {
  late _MockRealtimeChannel channel;

  setUp(() {
    channel = _MockRealtimeChannel();
    when(() => channel.unsubscribe()).thenAnswer((_) async => 'ok');
  });

  test(
    'failed fire preserves both choices and retries the exact move',
    () async {
      final gateway = _FakePaintBallGateway(_session(), channel);
      final sound = FakeSoundService();
      final haptics = FakeHaptics();
      final events = <String>[];
      final container = _container(
        gateway: gateway,
        sound: sound,
        haptics: haptics,
        analytics: PaintBallAnalytics(capture: (name, _) => events.add(name)),
      );
      addTearDown(container.dispose);

      final notifier = container.read(paintBallSessionProvider.notifier);
      await notifier.loadSession('session-1');
      notifier.selectHide(1);
      notifier.selectShot(2);

      gateway.turnError = const PaintBallApiError(
        error: true,
        code: 'RATE_LIMITED',
        message: 'Too many attempts. Please wait a moment.',
      );
      await notifier.takeTurn();

      var state = container.read(paintBallSessionProvider);
      expect(state.canFire, isTrue);
      expect(state.hidePosition, 1);
      expect(state.shotPosition, 2);
      expect(state.errorMessage, contains('Too many attempts'));

      gateway
        ..turnError = null
        ..nextResult = const PaintBallTurnResult(
          roundNumber: 2,
          livesA: 3,
          livesB: 2,
          currentTurnUserId: 'user-b',
          knockout: false,
          doubleKnockout: false,
          opener: PaintBallHalf(
            userId: 'user-a',
            hidePosition: 1,
            shotPosition: 2,
            shotResult: 'hit',
          ),
          closer: PaintBallHalf(
            userId: 'user-b',
            hidePosition: 2,
            shotPosition: 0,
            shotResult: 'miss',
          ),
        );
      await notifier.takeTurn();

      state = container.read(paintBallSessionProvider);
      expect(gateway.turnCalls, hasLength(2));
      expect(gateway.turnCalls.every((call) => call.round == 2), isTrue);
      expect(gateway.turnCalls.every((call) => call.hide == 1), isTrue);
      expect(gateway.turnCalls.every((call) => call.shot == 2), isTrue);
      // A resolved round queues a replay carrying BOTH halves -- the
      // field cannot animate the exchange without the partner's position,
      // and that position only exists once the round has resolved.
      expect(state.pendingReplay, isNotNull);
      expect(state.pendingReplay!.mine.shotResult, 'hit');
      expect(state.pendingReplay!.theirs.hidePosition, 2);
      expect(state.awaitingPartner, isFalse);
      expect(
        events.where((event) => event == PaintBallAnalytics.shotFiredEvent),
        hasLength(2),
      );
      expect(events, contains(PaintBallAnalytics.shotHitEvent));
    },
  );

  test('opening a round reveals nothing and queues no replay', () async {
    // The half that opens a round must not leak the partner's position or
    // pretend to an outcome: nothing has resolved, and a client that
    // animated a replay here would be inventing one.
    final gateway = _FakePaintBallGateway(_session(currentRound: 1), channel)
      ..nextResult = const PaintBallTurnResult(
        roundNumber: 1,
        livesA: 3,
        livesB: 3,
        currentTurnUserId: 'user-b',
        knockout: false,
        doubleKnockout: false,
      );
    final sound = FakeSoundService();
    final container = _container(
      gateway: gateway,
      sound: sound,
      haptics: FakeHaptics(),
      analytics: const PaintBallAnalytics(),
    );
    addTearDown(container.dispose);

    final notifier = container.read(paintBallSessionProvider.notifier);
    await notifier.loadSession('session-1');
    notifier
      ..selectHide(0)
      ..selectShot(1);
    await notifier.takeTurn();

    final state = container.read(paintBallSessionProvider);
    expect(state.awaitingPartner, isTrue);
    expect(state.pendingReplay, isNull);
    expect(state.revealedPartnerPosition, isNull);
    expect(state.showHitFeedback, isFalse);
    expect(state.showMissFeedback, isFalse);
    expect(sound.played, isNot(contains(AppSound.gameHit)));
    expect(sound.played, isNot(contains(AppSound.gameMiss)));
  });

  test('unexpected failures never leak exception details', () async {
    final gateway = _FakePaintBallGateway(_session(), channel)
      ..turnError = Exception('postgres host and internal table details');
    final container = _container(
      gateway: gateway,
      sound: FakeSoundService(),
      haptics: FakeHaptics(),
      analytics: const PaintBallAnalytics(),
    );
    addTearDown(container.dispose);

    final notifier = container.read(paintBallSessionProvider.notifier);
    await notifier.loadSession('session-1');
    notifier
      ..selectHide(0)
      ..selectShot(1);
    await notifier.takeTurn();

    expect(
      container.read(paintBallSessionProvider).errorMessage,
      'Could not send that turn. Please try again.',
    );
    expect(
      container.read(paintBallSessionProvider).errorMessage,
      isNot(contains('postgres')),
    );
  });

  test(
    'declining records abandonment without pretending to complete',
    () async {
      final gateway = _FakePaintBallGateway(
        _session(status: 'invited'),
        channel,
      );
      final container = _container(
        gateway: gateway,
        sound: FakeSoundService(),
        haptics: FakeHaptics(),
        analytics: const PaintBallAnalytics(),
      );
      addTearDown(container.dispose);

      final notifier = container.read(paintBallSessionProvider.notifier);
      await notifier.loadSession('session-1');
      await notifier.declineSession('session-1');

      final session = container.read(paintBallSessionProvider).session!;
      expect(session.isAbandoned, isTrue);
      expect(session.abandonedAt, isNotNull);
      expect(session.completedAt, isNull);
    },
  );

  test(
    'loser can decline once and the session reaches the end recap',
    () async {
      final gateway = _FakePaintBallGateway(
        _session(
          turnUserId: null,
          livesA: 0,
          winnerUserId: 'user-b',
          penaltyStatus: 'pending',
        ),
        channel,
      );
      final events = <String>[];
      final container = _container(
        gateway: gateway,
        sound: FakeSoundService(),
        haptics: FakeHaptics(),
        analytics: PaintBallAnalytics(capture: (name, _) => events.add(name)),
      );
      addTearDown(container.dispose);

      final notifier = container.read(paintBallSessionProvider.notifier);
      await notifier.loadSession('session-1');
      expect(
        container.read(paintBallSessionProvider).phase,
        PaintBallGamePhase.knockout,
      );

      await notifier.resolvePenalty(completed: false);

      final state = container.read(paintBallSessionProvider);
      expect(gateway.penaltyOutcomes, ['declined']);
      expect(state.phase, PaintBallGamePhase.ended);
      expect(state.session!.penaltyStatus, 'declined');
      expect(state.session!.status, 'completed');
      expect(events, contains(PaintBallAnalytics.penaltyDeclinedEvent));
      expect(events, contains(PaintBallAnalytics.sessionCompletedEvent));
    },
  );

  test(
    'pending penalty reveal is announced once and only to the loser',
    () async {
      final loserSound = FakeSoundService();
      final loserHaptics = FakeHaptics();
      final loserGateway = _FakePaintBallGateway(
        _session(
          turnUserId: null,
          livesA: 0,
          winnerUserId: 'user-b',
          penaltyStatus: 'pending',
        ),
        channel,
      );
      final loserContainer = _container(
        gateway: loserGateway,
        sound: loserSound,
        haptics: loserHaptics,
        analytics: const PaintBallAnalytics(),
      );
      addTearDown(loserContainer.dispose);

      final loserNotifier = loserContainer.read(
        paintBallSessionProvider.notifier,
      );
      await loserNotifier.loadSession('session-1');
      await loserNotifier.loadSession('session-1');

      expect(
        loserSound.played.where((sound) => sound == AppSound.gamePenaltyReveal),
        hasLength(1),
      );
      expect(loserHaptics.lightCount, 1);

      final winnerSound = FakeSoundService();
      final winnerContainer = _container(
        gateway: _FakePaintBallGateway(
          _session(
            turnUserId: null,
            livesB: 0,
            winnerUserId: 'user-a',
            penaltyStatus: 'pending',
          ),
          channel,
        ),
        sound: winnerSound,
        haptics: FakeHaptics(),
        analytics: const PaintBallAnalytics(),
      );
      addTearDown(winnerContainer.dispose);

      await winnerContainer
          .read(paintBallSessionProvider.notifier)
          .loadSession('session-1');
      expect(winnerSound.played, isNot(contains(AppSound.gamePenaltyReveal)));
    },
  );

  test('a player always has a position to stand in', () async {
    // THE BUG THIS EXISTS FOR: hidePosition started null, so the board
    // opened with no character on it at all. Every widget test passed
    // because they all supplied a position explicitly -- none of them
    // asked what the provider actually hands the field on a fresh turn.
    final gateway = _FakePaintBallGateway(_session(), channel);
    final container = _container(
      gateway: gateway,
      sound: FakeSoundService(),
      haptics: FakeHaptics(),
      analytics: const PaintBallAnalytics(),
    );
    addTearDown(container.dispose);

    await container
        .read(paintBallSessionProvider.notifier)
        .loadSession('session-1');

    final state = container.read(paintBallSessionProvider);
    expect(
      state.hidePosition,
      isNotNull,
      reason: 'a player is dealt a cover; they do not start nowhere',
    );
    expect(state.hidePosition, inInclusiveRange(0, 2));
  });

  test('a later round keeps you where you were', () async {
    // Staying put must be a real choice made by doing nothing. If each
    // round re-rolled, a player would be teleported between turns and
    // "stay where you are" would be impossible to express.
    final gateway = _FakePaintBallGateway(
      _session(currentRound: 3).copyWith(
        rounds: [
          PaintBallRound(
            roundNumber: 2,
            shotResult: 'miss',
            lifeLost: false,
            createdAt: DateTime.now(),
            activePartnerId: 'user-a',
            hidePosition: 2,
          ),
        ],
      ),
      channel,
    );
    final container = _container(
      gateway: gateway,
      sound: FakeSoundService(),
      haptics: FakeHaptics(),
      analytics: const PaintBallAnalytics(),
    );
    addTearDown(container.dispose);

    await container
        .read(paintBallSessionProvider.notifier)
        .loadSession('session-1');

    expect(
      container.read(paintBallSessionProvider).hidePosition,
      2,
      reason: 'the previous cover carries forward',
    );
  });
}
