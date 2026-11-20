import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_content_width.dart';
import 'package:attune/features/games/platform/shell/game_coach.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/providers/game_session_live_provider.dart';
import 'package:attune/features/games/this_or_that/data/models/custom_this_or_that_question.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_custom_providers.dart'
    as custom;
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/end_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_source_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/reveal_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/session_history_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_custom_create_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_custom_list_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_session_router_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/waiting_screen.dart';
import 'package:attune/features/games/this_or_that/this_or_that_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../platform/support/game_test_support.dart';
import 'this_or_that_fakes.dart';

/// One of This or That's screens, as a test pumps it.
typedef ShellScreen =
    ({
      Widget Function() build,
      List<Override> Function() overrides,
      Future<void> Function(WidgetTester tester)? then,
    });

final CustomThisOrThatQuestion deckQuestion = CustomThisOrThatQuestion(
  id: 'custom-1',
  userId: 'user-a',
  questionText: 'How would we spend a free weekend?',
  optionA: 'Stay home and cook something big',
  optionB: 'Take a train somewhere new',
  tone: 'playful',
  isPrivate: false,
  timesUsed: 3,
  createdAt: DateTime(2026, 9, 1),
);

ThisOrThatSession _finished({
  required String id,
  required String tone,
  required int matches,
  required DateTime on,
}) => ThisOrThatSession(
  id: id,
  relationshipId: 'rel-1',
  initiatorId: 'user-a',
  tone: tone,
  status: 'completed',
  totalRounds: 10,
  currentRound: 10,
  matchCount: matches,
  totalRoundsCompleted: 10,
  createdAt: on,
);

/// A round's reveal: you chose Stay in; Ama chose [partner].
RevealScreen _reveal({required String partner}) => RevealScreen(
  questionText: 'Friday night: stay in or go out?',
  userChoice: 'a',
  userChoiceText: 'Stay in',
  userChoiceEmoji: '🛋️',
  partnerChoice: partner,
  partnerChoiceText: partner == 'a' ? 'Stay in' : 'Go out',
  partnerChoiceEmoji: partner == 'a' ? '🛋️' : '✨',
  partnerName: 'Ama',
  roundNumber: 3,
  totalRounds: 10,
  isMatch: partner == 'a',
  hasPrevious: true,
  onPrevious: () {},
  onNext: () {},
);

/// The end of a game with Ama: [matches] of 10, and the round worth
/// talking about.
ShellScreen _end({required int matches}) => (
  build:
      () => EndScreen(
        matchCount: matches,
        totalRounds: 10,
        mostInterestingPick: const {
          'question_text': 'Friday night: stay in or go out?',
          'answer_a': 'a',
          'answer_b': 'b',
          'answer_a_text': 'Stay in',
          'answer_b_text': 'Go out',
          'answer_a_emoji': '🛋️',
          'answer_b_emoji': '✨',
        },
        onPlayAgain: () {},
        onTryAnotherGame: () {},
      ),
  overrides:
      () => [gamePartnerNameProvider.overrideWith((_) async => 'Ama')],
  then: null,
);

/// The screens moved onto the shell that have pictures: the question deck
/// list, the write-a-question form, past games, the next-card chooser, the
/// invitation decision, waiting for the partner, the reveal on a match
/// and on a difference, and the end on a high score and a low one. The
/// reveal's burst and the end's tiles are animations; these are the
/// settled screens, under reduced motion.
Map<String, ShellScreen> thisOrThatShellScreens() => {
  'deck_list': (
    build: () => const ThisOrThatCustomListScreen(),
    overrides:
        () => [
          custom.myThisOrThatCustomQuestionsProvider.overrideWith(
            (_) async => [deckQuestion],
          ),
          custom.partnerThisOrThatCustomQuestionsProvider.overrideWith(
            (_) async => const [],
          ),
          custom.partnerNameProvider.overrideWith((_) async => 'Ama'),
        ],
    then: null,
  ),
  'write_form': (
    build: () => const ThisOrThatCustomCreateScreen(),
    overrides: () => const [],
    then: (tester) async {
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), 'Perfect Sunday?');
      await tester.enterText(fields.at(1), 'Stay home');
      await tester.pumpAndSettle();
    },
  ),
  'past_games': (
    build: () => const SessionHistoryScreen(),
    overrides:
        () => [
          completedSessionsProvider.overrideWith(
            (_) async => [
              _finished(
                id: 'g1',
                tone: 'playful',
                matches: 7,
                on: DateTime(2026, 11, 14),
              ),
              _finished(
                id: 'g2',
                tone: 'romantic',
                matches: 4,
                on: DateTime(2026, 11, 2),
              ),
            ],
          ),
        ],
    then: null,
  ),
  'next_card': (
    build:
        () => const QuestionSourceScreen(
          sessionId: 'session-1',
          nextRound: 4,
          totalRounds: 10,
          isChooser: true,
          chooserName: 'You',
          currentUserId: 'user-a',
          partnerUserId: 'user-b',
          partnerName: 'Ama',
        ),
    overrides:
        () => [
          thisOrThatRepositoryProvider.overrideWithValue(
            MockThisOrThatRepository(),
          ),
          currentUserIdProvider.overrideWithValue('user-a'),
        ],
    then: null,
  ),
  'invitation': (
    build: () => const ThisOrThatSessionRouterScreen(sessionId: 's1'),
    overrides:
        () => [
          thisOrThatRepositoryProvider.overrideWithValue(
            MockThisOrThatRepository(),
          ),
          currentUserIdProvider.overrideWithValue('user-a'),
          sessionProvider.overrideWith(
            (_, __) async => thisOrThatSession(
              initiatorId: 'user-b',
              status: 'invited',
              currentRound: 1,
            ),
          ),
          partnerNameProvider.overrideWith((_) async => 'Ama'),
          relationshipMembersProvider.overrideWith(
            (_, __) async => (userA: 'user-a', userB: 'user-b'),
          ),
          gameSessionLiveProvider.overrideWith(
            (_, __) => const Stream<void>.empty(),
          ),
        ],
    then: null,
  ),
  'waiting': (
    build:
        () => const WaitingScreen(
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
    overrides:
        () => [
          thisOrThatRepositoryProvider.overrideWithValue(
            MockThisOrThatRepository(),
          ),
          currentUserIdProvider.overrideWithValue('user-a'),
        ],
    then: null,
  ),
  'reveal_match': (
    build: () => _reveal(partner: 'a'),
    overrides: () => const [],
    then: null,
  ),
  'reveal_differ': (
    build: () => _reveal(partner: 'b'),
    overrides: () => const [],
    then: null,
  ),
  'end': _end(matches: 7),
  'end_low': _end(matches: 1),
};

/// The question screen's pictures: before a choice, with THIS chosen, and
/// a first-time player's tutorial over it, on a phone and on the smallest
/// one. [stored] is what the device remembers; every picture but the
/// tutorial's has the tutorial seen.
Map<String, ({ShellScreen screen, Map<String, Object> stored, Size size})>
thisOrThatQuestionScreens() {
  final seen = {GameCoachStore.key('this_or_that'): true};
  ShellScreen question({Future<void> Function(WidgetTester)? then}) => (
    build:
        () => const QuestionScreen(
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
        ),
    overrides: () {
      final repository = MockThisOrThatRepository();
      when(
        () => repository.submitAnswer(
          roundId: any(named: 'roundId'),
          userId: any(named: 'userId'),
          choice: any(named: 'choice'),
          isPartnerA: any(named: 'isPartnerA'),
        ),
      ).thenAnswer((_) async {});
      return [
        thisOrThatRepositoryProvider.overrideWithValue(repository),
        thisOrThatAnswerOutboxProvider.overrideWithValue(MemoryAnswerOutbox()),
        currentUserIdProvider.overrideWithValue('user-a'),
      ];
    },
    then: then,
  );

  return {
    'question': (screen: question(), stored: seen, size: phone),
    'question_this': (
      screen: question(
        then: (tester) async {
          await tester.tap(find.text('THIS'));
          await tester.pumpAndSettle();
        },
      ),
      stored: seen,
      size: phone,
    ),
    'question_coach': (screen: question(), stored: const {}, size: phone),
    // The smallest phone in use: the bubble still clears the tabs.
    'question_coach_small': (
      screen: question(),
      stored: const {},
      size: const Size(320, 568),
    ),
  };
}

/// Screens with a picture on the smallest phone in use, 320x568: the
/// reveal, with Previous round, keeps its verdict above the buttons.
Map<String, ({ShellScreen screen, Map<String, Object> stored, Size size})>
thisOrThatSmallScreens() => {
  'reveal_small': (
    screen: (
      build: () => _reveal(partner: 'b'),
      overrides: () => const [],
      then: null,
    ),
    stored: const {},
    size: const Size(320, 568),
  ),
};

/// Pumps [screen] on [size] in a light app, on a device that remembers
/// [stored].
Future<void> pumpShellScreen(
  WidgetTester tester,
  ShellScreen screen, {
  Size size = phone,
  bool reduceMotion = true,
  Map<String, Object> stored = const {},
}) async {
  useSurface(tester, size);
  await tester.pumpWidget(
    gameHost(
      screen.build(),
      prefs: await testPrefs(stored),
      reduceMotion: reduceMotion,
      overrides: screen.overrides(),
    ),
  );
  await tester.pumpAndSettle();
  await screen.then?.call(tester);
}

/// The backdrop's colour at [y] on a screen [height] tall: This or That's
/// colour at the top, fading to the ground a little past halfway.
Color backdropAt(double y, double height) {
  final gradient = thisOrThatTheme.backdrop;
  final t = (y / height).clamp(0.0, 1.0);
  final stops = gradient.stops!;
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i]) {
      final local = (t - stops[i - 1]) / (stops[i] - stops[i - 1]);
      return Color.lerp(gradient.colors[i - 1], gradient.colors[i], local)!;
    }
  }
  return gradient.colors.last;
}

/// Words written straight on the backdrop in a screen's body, and how well
/// each can be read against the backdrop where it sits.
///
/// [inkOnGround] judges everything against the ground, which is right for
/// the lower half of a screen. The top of a This or That screen is the
/// game's orange, and the first lines of a body sit on it. Words inside a
/// card, a chip or a field are on that surface instead and left out, as
/// are words on a white tile or button. The header is the shell's and is
/// held to its own 3:1 bar for titles by the shell's tests.
///
/// [needed] is the WCAG bar for the text's size, lowered to what white ink
/// reaches at that spot: just under the header the orange is light enough
/// that nothing reaches 4.5:1, and there the most readable ink, white, is
/// what a screen can do.
List<({String text, double contrast, double needed})> inkOnBackdrop(
  WidgetTester tester,
) {
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final found = <({String text, double contrast, double needed})>[];
  final body = find.byType(GameContentWidth);
  final texts = find.descendant(of: body, matching: find.byType(RichText));
  for (final element in texts.evaluate()) {
    var onSurface = false;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is GameContentWidth) return false;
      if (widget is GameTile ||
          widget is GamePrimaryButton ||
          widget is GameSecondaryButton ||
          widget is EditableText ||
          (widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color != null) ||
          (widget is Material &&
              widget.type != MaterialType.transparency &&
              widget.color != null &&
              widget.color!.a > 0)) {
        onSurface = true;
        return false;
      }
      return true;
    });
    if (onSurface) continue;

    final rich = element.widget as RichText;
    final text = rich.text.toPlainText();
    if (text.trim().isEmpty) continue;
    final isIcon = text.runes.every(
      (rune) => (rune >= 0xE000 && rune <= 0xF8FF) || rune >= 0xF0000,
    );
    if (isIcon) continue;

    final style = rich.text.style;
    final ink = style?.color ?? const Color(0xFF000000);
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    // The lighter end of the line's height is the harder one to read on.
    final lightest = backdropAt(rect.top, height);
    final worst = contrast(Color.alphaBlend(ink, lightest), lightest);
    final best = contrast(GameTheme.onGround, lightest);
    final size = style?.fontSize ?? 14;
    final bold = (style?.fontWeight?.value ?? 400) >= 700;
    final large = size >= 24 || (size >= 18.66 && bold);
    final bar = large ? 3.0 : 4.5;
    found.add((text: text, contrast: worst, needed: bar < best ? bar : best));
  }
  return found;
}
