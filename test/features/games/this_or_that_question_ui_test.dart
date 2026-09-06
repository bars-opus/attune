import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/data/repositories/this_or_that_repository.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/end_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/reveal_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/waiting_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements ThisOrThatRepository {}

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
}) {
  return ProviderScope(
    overrides: [
      thisOrThatRepositoryProvider.overrideWithValue(repository),
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
      () => repository.watchRound(any()),
    ).thenAnswer((_) => const Stream<GameRound>.empty());
    when(
      () => repository.submitAnswer(
        roundId: any(named: 'roundId'),
        userId: any(named: 'userId'),
        choice: any(named: 'choice'),
        isPartnerA: any(named: 'isPartnerA'),
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
    expect(find.text('Lock in Go out'), findsOneWidget);
    expect(sounds.played, [AppSound.gameTap]);
    expect(haptics.selectionCount, 1);

    await tester.tap(find.text('Lock in Go out'));
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
    expect(find.textContaining('lost'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
