import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_content_width.dart';
import 'package:attune/features/games/presentation/providers/game_session_live_provider.dart';
import 'package:attune/features/games/this_or_that/data/models/custom_this_or_that_question.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_custom_providers.dart'
    as custom;
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_source_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/session_history_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_custom_create_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_custom_list_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_session_router_screen.dart';
import 'package:attune/features/games/this_or_that/this_or_that_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// The screens this task moved and has pictures of: the question deck
/// list, the write-a-question form, past games, the next-card chooser and
/// the invitation decision.
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
};

/// Pumps [screen] on [size] in a light app.
Future<void> pumpShellScreen(
  WidgetTester tester,
  ShellScreen screen, {
  Size size = phone,
  bool reduceMotion = true,
}) async {
  useSurface(tester, size);
  await tester.pumpWidget(
    gameHost(
      screen.build(),
      prefs: await testPrefs(),
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
