import 'dart:async';
import 'dart:io';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/data/repositories/this_or_that_repository.dart';
import 'package:attune/features/games/this_or_that/data/services/this_or_that_answer_outbox.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/end_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_source_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/reveal_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/session_detail_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/session_history_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_session_router_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/tone_selector_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/waiting_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/games/presentation/providers/game_session_live_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements ThisOrThatRepository {}

class _MemoryAnswerOutbox implements ThisOrThatAnswerOutbox {
  final Map<String, PendingThisOrThatAnswer> pending = {};

  String _key(String userId, String roundId) => '$userId:$roundId';

  @override
  Future<PendingThisOrThatAnswer?> read({
    required String userId,
    required String roundId,
  }) async => pending[_key(userId, roundId)];

  @override
  Future<void> remove({required String userId, required String roundId}) async {
    pending.remove(_key(userId, roundId));
  }

  @override
  Future<void> save({
    required String userId,
    required String roundId,
    required String choice,
  }) async {
    pending[_key(userId, roundId)] = PendingThisOrThatAnswer(
      roundId: roundId,
      choice: choice,
      savedAt: DateTime.now(),
    );
  }
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap({
  required Widget child,
  required ThisOrThatRepository repository,
  Brightness brightness = Brightness.light,
  FakeSoundService? sounds,
  FakeHaptics? haptics,
  ThisOrThatAnswerOutbox? answerOutbox,
}) {
  return ProviderScope(
    overrides: [
      thisOrThatRepositoryProvider.overrideWithValue(repository),
      thisOrThatAnswerOutboxProvider.overrideWithValue(
        answerOutbox ?? _MemoryAnswerOutbox(),
      ),
      currentUserIdProvider.overrideWithValue('user-a'),
      soundServiceProvider.overrideWithValue(sounds ?? FakeSoundService()),
      hapticsProvider.overrideWithValue(haptics ?? FakeHaptics()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          disableAnimations: true,
        ),
        child: child,
      ),
    ),
  );
}

QuestionScreen _question({VoidCallback? onSubmitted}) => QuestionScreen(
  roundId: 'round-3',
  questionText: 'Friday night: stay in or go out?',
  optionA: 'Stay in',
  optionB: 'Go out',
  emojiA: '🛋️',
  emojiB: '✨',
  roundNumber: 3,
  totalRounds: 10,
  tone: 'playful',
  isPartnerA: true,
  partnerName: 'Ama',
  onAnswerSubmitted: onSubmitted,
);

void main() {
  late _MockRepository repository;

  setUp(() {
    repository = _MockRepository();
    when(
      () => repository.submitAnswer(
        roundId: any(named: 'roundId'),
        userId: any(named: 'userId'),
        choice: any(named: 'choice'),
        isPartnerA: any(named: 'isPartnerA'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => repository.prepareNextRound(
        sessionId: any(named: 'sessionId'),
        roundNumber: any(named: 'roundNumber'),
        source: any(named: 'source'),
        customOwnerId: any(named: 'customOwnerId'),
      ),
    ).thenAnswer((_) async => false);
    when(
      () => repository.advanceSession(
        sessionId: any(named: 'sessionId'),
        nextRound: any(named: 'nextRound'),
        matchCount: any(named: 'matchCount'),
        totalRoundsCompleted: any(named: 'totalRoundsCompleted'),
        isCompleted: any(named: 'isCompleted'),
      ),
    ).thenAnswer((_) async {});
  });

  testWidgets('question reads as a two-sided game and shows round progress', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_wrap(child: _question(), repository: repository));
    await tester.pump();

    expect(find.text('ROUND 3 OF 10'), findsOneWidget);
    expect(find.text('Friday night: stay in or go out?'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ThisOrThatChoiceCard && widget.text == 'Stay in',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ThisOrThatChoiceCard && widget.text == 'Go out',
      ),
      findsOneWidget,
    );
    expect(find.text('Choose your side'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pick gives feedback and submits the option key', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final sounds = FakeSoundService();
    final haptics = FakeHaptics();
    var submitted = false;
    await tester.pumpWidget(
      _wrap(
        child: _question(onSubmitted: () => submitted = true),
        repository: repository,
        sounds: sounds,
        haptics: haptics,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Go out'));
    await tester.pump();
    expect(find.text('Lock in That'), findsOneWidget);
    expect(sounds.played, [AppSound.gameTap]);
    expect(haptics.selectionCount, 1);

    await tester.tap(find.text('Lock in That'));
    await tester.pump();
    await tester.pump();
    expect(submitted, isTrue);
    verify(
      () => repository.submitAnswer(
        roundId: 'round-3',
        userId: 'user-a',
        choice: 'b',
        isPartnerA: true,
      ),
    ).called(1);
  });

  testWidgets('a network failure keeps the pick in the local outbox', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final outbox = _MemoryAnswerOutbox();
    when(
      () => repository.submitAnswer(
        roundId: any(named: 'roundId'),
        userId: any(named: 'userId'),
        choice: any(named: 'choice'),
        isPartnerA: any(named: 'isPartnerA'),
      ),
    ).thenThrow(const SocketException('offline'));

    await tester.pumpWidget(
      _wrap(child: _question(), repository: repository, answerOutbox: outbox),
    );
    await tester.pump();
    await tester.tap(find.text('Stay in'));
    await tester.pump();
    await tester.tap(find.text('Lock in This'));
    await tester.pump();
    await tester.pump();

    expect(outbox.pending['user-a:round-3']?.choice, 'a');
    expect(find.byKey(const Key('answer-waiting-to-connect')), findsOneWidget);
    expect(find.textContaining('saved on this device'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a restored offline pick retries automatically', (tester) async {
    _usePhoneViewport(tester);
    final outbox = _MemoryAnswerOutbox();
    await outbox.save(userId: 'user-a', roundId: 'round-3', choice: 'b');
    var submitted = false;

    await tester.pumpWidget(
      _wrap(
        child: _question(onSubmitted: () => submitted = true),
        repository: repository,
        answerOutbox: outbox,
      ),
    );
    await tester.pumpAndSettle();

    expect(submitted, isTrue);
    expect(outbox.pending, isEmpty);
    verify(
      () => repository.submitAnswer(
        roundId: 'round-3',
        userId: 'user-a',
        choice: 'b',
        isPartnerA: true,
      ),
    ).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waiting lets a player reopen and change their saved pick', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        repository: repository,
        child: WaitingScreen(
          sessionId: 'session-1',
          roundId: 'round-3',
          questionText: 'Friday night: stay in or go out?',
          userChoice: 'a',
          userChoiceText: 'Stay in',
          userChoiceEmoji: '🛋️',
          optionA: 'Stay in',
          optionB: 'Go out',
          emojiA: '🛋️',
          emojiB: '✨',
          roundNumber: 3,
          totalRounds: 10,
          isPartnerA: true,
          partnerName: 'Ama',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ama is choosing'), findsOneWidget);
    await tester.tap(find.text('Change my pick'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Go out'));
    await tester.tap(find.text('Go out'));
    await tester.pump();
    await tester.pump();

    verify(
      () => repository.submitAnswer(
        roundId: 'round-3',
        userId: 'user-a',
        choice: 'b',
        isPartnerA: true,
      ),
    ).called(1);
    expect(find.text('✨ Go out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('match reveal stages both named picks without phone overflow', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        repository: repository,
        brightness: Brightness.dark,
        child: RevealScreen(
          questionText: 'Pick the perfect slow morning',
          userChoice: 'a',
          userChoiceText: 'Coffee in bed',
          userChoiceEmoji: '☕',
          partnerChoice: 'a',
          partnerChoiceText: 'Coffee in bed',
          partnerChoiceEmoji: '☕',
          partnerName: 'Ama',
          roundNumber: 4,
          totalRounds: 10,
          isMatch: true,
          onNext: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('AMA'), findsOneWidget);
    expect(find.text('Same wavelength'), findsOneWidget);
    expect(find.text('Next round'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('next-card chooser can open either personal deck', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        repository: repository,
        child: const QuestionSourceScreen(
          sessionId: 'session-1',
          nextRound: 4,
          totalRounds: 10,
          isChooser: true,
          chooserName: 'You',
          currentUserId: 'user-a',
          partnerUserId: 'user-b',
          partnerName: 'Ama',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Preset deck'), findsOneWidget);
    expect(find.text('Our questions'), findsOneWidget);
    await tester.tap(find.text('Our questions'));
    await tester.pump();

    expect(find.text('My deck'), findsOneWidget);
    expect(find.text("Ama's deck"), findsOneWidget);
    expect(find.text('Choose another source'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('next-card chooser submits one server-authoritative choice', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final pending = Completer<bool>();
    when(
      () => repository.prepareNextRound(
        sessionId: 'session-1',
        roundNumber: 4,
        source: 'preset',
        customOwnerId: null,
      ),
    ).thenAnswer((_) => pending.future);
    await tester.pumpWidget(
      _wrap(
        repository: repository,
        child: const QuestionSourceScreen(
          sessionId: 'session-1',
          nextRound: 4,
          totalRounds: 10,
          isChooser: true,
          chooserName: 'You',
          currentUserId: 'user-a',
          partnerUserId: 'user-b',
          partnerName: 'Ama',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Preset deck'));
    await tester.tap(find.text('Preset deck'));
    await tester.pump();
    verify(
      () => repository.prepareNextRound(
        sessionId: 'session-1',
        roundNumber: 4,
        source: 'preset',
        customOwnerId: null,
      ),
    ).called(1);

    pending.complete(false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reveal ignores repeated next taps while advancing', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final advance = Completer<void>();
    var advanceCount = 0;
    await tester.pumpWidget(
      _wrap(
        repository: repository,
        child: RevealScreen(
          questionText: 'Pick the perfect slow morning',
          userChoice: 'a',
          userChoiceText: 'Coffee in bed',
          userChoiceEmoji: '☕',
          partnerChoice: 'b',
          partnerChoiceText: 'A sunrise walk',
          partnerChoiceEmoji: '🌅',
          partnerName: 'Ama',
          roundNumber: 4,
          totalRounds: 10,
          isMatch: false,
          onNext: () {
            advanceCount++;
            return advance.future;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Next round'));
    await tester.tap(find.text('Next round'), warnIfMissed: false);
    await tester.pump();
    expect(advanceCount, 1);

    advance.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'past reveal exposes previous navigation without replaying feedback',
    (tester) async {
      _usePhoneViewport(tester);
      final sounds = FakeSoundService();
      final haptics = FakeHaptics();
      var previousCount = 0;
      await tester.pumpWidget(
        _wrap(
          repository: repository,
          sounds: sounds,
          haptics: haptics,
          child: RevealScreen(
            questionText: 'Pick the perfect slow morning',
            userChoice: 'a',
            userChoiceText: 'Coffee in bed',
            userChoiceEmoji: '☕',
            partnerChoice: 'a',
            partnerChoiceText: 'Coffee in bed',
            partnerChoiceEmoji: '☕',
            partnerName: 'Ama',
            roundNumber: 3,
            totalRounds: 10,
            isMatch: true,
            celebrate: false,
            hasPrevious: true,
            onPrevious: () => previousCount++,
            nextLabel: 'Current round',
            onNext: () {},
          ),
        ),
      );
      await tester.pump();

      expect(sounds.played, isEmpty);
      expect(haptics.mediumCount, 0);
      expect(find.text('Current round'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      expect(previousCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test('redacted round exposes answer presence without the partner choice', () {
    final round = GameRound.fromJson({
      'id': 'round-2',
      'session_id': 'session-1',
      'round_number': 2,
      'question_id': 'question-2',
      'answer_a': null,
      'answer_b': null,
      'has_answer_a': false,
      'has_answer_b': true,
      'both_answered': false,
      'game_questions': {
        'question_text': 'Morning or midnight?',
        'option_a': 'Morning',
        'option_b': 'Midnight',
      },
    });

    expect(round.answerB, isNull);
    expect(round.hasUserBAnswered, isTrue);
    expect(round.bothAnswered, isFalse);
  });

  testWidgets('recap labels the current player correctly for partner B', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final session = ThisOrThatSession(
      id: 'session-1',
      relationshipId: 'relationship-1',
      initiatorId: 'user-a',
      tone: 'connecting',
      status: 'completed',
      totalRounds: 1,
      currentRound: 1,
      matchCount: 0,
      totalRoundsCompleted: 1,
      createdAt: DateTime(2026, 9, 1),
    );
    final round = GameRound(
      id: 'round-1',
      sessionId: session.id,
      roundNumber: 1,
      answerA: 'a',
      answerB: 'b',
      bothAnswered: true,
      questionText: 'Breakfast or dinner date?',
      optionA: 'Breakfast together',
      optionB: 'Dinner together',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-b'),
          sessionProvider.overrideWith((_, __) async => session),
          sessionRoundsProvider.overrideWith((_, __) async => [round]),
          relationshipMembersProvider.overrideWith(
            (_, __) async => (userA: 'user-a', userB: 'user-b'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const SessionDetailScreen(sessionId: 'session-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final yourPick = tester.getTopLeft(find.text('Dinner together'));
    final partnerPick = tester.getTopLeft(find.text('Breakfast together'));
    expect(yourPick.dx, lessThan(partnerPick.dx));
    expect(find.text('A game worth talking about'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history keeps its loading state until the first page resolves', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final history = Completer<List<ThisOrThatSession>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          completedSessionsProvider.overrideWith((_) => history.future),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const SessionHistoryScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('this-or-that-history-loading')),
      findsOneWidget,
    );
    expect(find.text('Your reveals will live here'), findsNothing);

    history.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Your reveals will live here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overdue waiting round offers a reminder immediately', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        repository: repository,
        child: WaitingScreen(
          sessionId: 'session-1',
          roundId: 'round-3',
          questionText: 'Friday night: stay in or go out?',
          userChoice: 'a',
          userChoiceText: 'Stay in',
          userChoiceEmoji: '🛋️',
          optionA: 'Stay in',
          optionB: 'Go out',
          roundNumber: 3,
          totalRounds: 10,
          isPartnerA: true,
          partnerName: 'Ama',
          answeredAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nudge Ama'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('end screen celebrates every score without calling it a loss', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        repository: repository,
        child: EndScreen(
          matchCount: 3,
          totalRounds: 10,
          mostInterestingPick: const {
            'question_text': 'Beach morning or city night?',
            'answer_a_text': 'Beach morning',
            'answer_b_text': 'City night',
            'answer_a_emoji': '🌊',
            'answer_b_emoji': '🌃',
          },
          onPlayAgain: () {},
          onTryAnotherGame: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Full of surprises'), findsOneWidget);
    expect(find.text('Talk about this one'.toUpperCase()), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('lost'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('final answered round reveals before session completion', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final session = ThisOrThatSession(
      id: 'session-final',
      relationshipId: 'relationship-1',
      initiatorId: 'user-a',
      tone: 'connecting',
      status: 'active',
      totalRounds: 1,
      currentRound: 1,
      matchCount: 0,
      totalRoundsCompleted: 0,
      createdAt: DateTime(2026, 9, 1),
    );
    final round = GameRound(
      id: 'round-final',
      sessionId: session.id,
      roundNumber: 1,
      answerA: 'a',
      answerB: 'b',
      bothAnswered: true,
      questionText: 'Sunrise or sunset?',
      optionA: 'Sunrise',
      optionB: 'Sunset',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          thisOrThatRepositoryProvider.overrideWithValue(repository),
          currentUserIdProvider.overrideWithValue('user-a'),
          soundServiceProvider.overrideWithValue(FakeSoundService()),
          hapticsProvider.overrideWithValue(FakeHaptics()),
          sessionProvider.overrideWith((_, __) async => session),
          sessionRoundsProvider.overrideWith((_, __) async => [round]),
          partnerNameProvider.overrideWith((_) async => 'Ama'),
          relationshipMembersProvider.overrideWith(
            (_, __) async => (userA: 'user-a', userB: 'user-b'),
          ),
          gameSessionLiveProvider.overrideWith(
            (_, __) => const Stream<void>.empty(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ThisOrThatSessionRouterScreen(sessionId: 'session-final'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A new thing to know'), findsOneWidget);
    expect(find.text('See our result'), findsOneWidget);
    expect(find.text('THE REVEAL'), findsOneWidget);
    await tester.tap(find.text('See our result'));
    await tester.pump();
    await tester.pump();
    verify(
      () => repository.advanceSession(
        sessionId: 'session-final',
        nextRound: 1,
        matchCount: 0,
        totalRoundsCompleted: 1,
        isCompleted: true,
      ),
    ).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tone selection has no overflow on a phone viewport', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        repository: repository,
        brightness: Brightness.dark,
        child: const ToneSelectorScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Intimate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
