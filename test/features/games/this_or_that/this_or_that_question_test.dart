import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_coach.dart';
import 'package:attune/features/games/platform/shell/game_settings_sheet.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_tab_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../platform/support/game_test_support.dart';
import 'support/this_or_that_fakes.dart';

/// This or That's question: the card in tiles, its feedback through the
/// shell, and the first-time tutorial over it.
void main() {
  // Real glyph widths: whether a tutorial step fits its bubble on a small
  // phone depends on them.
  setUpAll(loadGameTestFonts);

  const firstStep = 'Pull THIS or THAT forward to choose.';
  const lastStep =
      'When you have both picked, the two answers turn over together.';
  final seenCoach = {GameCoachStore.key('this_or_that'): true};

  QuestionScreen question({
    String partnerName = 'Ama',
    String questionText = 'Friday night: stay in or go out?',
    Key? key,
  }) => QuestionScreen(
    key: key,
    roundId: 'round-3',
    questionText: questionText,
    optionA: 'Stay in',
    optionB: 'Go out',
    emojiA: '🛋️',
    emojiB: '✨',
    roundNumber: 3,
    totalRounds: 10,
    tone: 'playful',
    isPartnerA: true,
    partnerName: partnerName,
  );

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object>? stored,
    FakeSoundService? sounds,
    FakeHaptics? haptics,
    Widget? screen,
    Size surface = phone,
    FakeViewPadding? padding,
    bool reduceMotion = true,
    ThemeData? theme,
  }) async {
    useSurface(tester, surface);
    if (padding != null) tester.view.padding = padding;
    final repository = MockThisOrThatRepository();
    when(
      () => repository.submitAnswer(
        roundId: any(named: 'roundId'),
        userId: any(named: 'userId'),
        choice: any(named: 'choice'),
        isPartnerA: any(named: 'isPartnerA'),
      ),
    ).thenAnswer((_) async {});
    await tester.pumpWidget(
      gameHost(
        screen ?? question(),
        prefs: await testPrefs(stored ?? seenCoach),
        sound: sounds,
        haptics: haptics,
        reduceMotion: reduceMotion,
        overrides: [
          thisOrThatRepositoryProvider.overrideWithValue(repository),
          thisOrThatAnswerOutboxProvider.overrideWithValue(
            MemoryAnswerOutbox(),
          ),
          currentUserIdProvider.overrideWithValue('user-a'),
        ],
        theme: theme,
      ),
    );
    // One frame to build, one for the tutorial's measurement to land.
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Finder tilesOfCard() => find.descendant(
    of: find.byType(ThisOrThatTabCard),
    matching: find.byType(GameTile),
  );

  Rect tabRow(WidgetTester tester) {
    final tiles = tilesOfCard();
    expect(tiles, findsNWidgets(3));
    return tiles
        .evaluate()
        .map((e) => tester.getRect(find.byElementPredicate((x) => x == e)))
        .reduce((a, b) => a.expandToInclude(b));
  }

  /// Every piece of text on the card and its tabs, with the colour it is
  /// drawn in and the colour of the face it is drawn on.
  ///
  /// The surface is the nearest painted box above the words -- a tab's
  /// face or the card's panel -- read from what is built, not from the
  /// palette, so a face that drew one colour while the card thought another
  /// would be caught. Emoji are left out: they are drawn in their own
  /// colours, whatever the style says.
  List<({String text, double contrast})> inkOnCard(WidgetTester tester) {
    final found = <({String text, double contrast})>[];
    final texts = find.descendant(
      of: find.byType(ThisOrThatTabCard),
      matching: find.byType(RichText),
    );
    for (final element in texts.evaluate()) {
      final rich = element.widget as RichText;
      final text = rich.text.toPlainText();
      if (!RegExp('[A-Za-z]').hasMatch(text)) continue;

      Color? surface;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color != null) {
          surface = (widget.decoration as BoxDecoration).color;
          return false;
        }
        return true;
      });
      expect(surface, isNotNull, reason: '"$text" is drawn on nothing');
      final ink = rich.text.style!.color!;
      found.add((
        text: text,
        contrast: contrast(Color.alphaBlend(ink, surface!), surface!),
      ));
    }
    return found;
  }

  Color panelColour(WidgetTester tester) {
    final panel = find.descendant(
      of: find.byKey(const ValueKey('this-or-that-card-panel')),
      matching: find.byType(DecoratedBox),
    );
    expect(panel, findsWidgets);
    return (tester.widget<DecoratedBox>(panel.first).decoration
            as BoxDecoration)
        .color!;
  }

  testWidgets('with sound switched off in settings, choosing is silent', (
    tester,
  ) async {
    // The control is this_or_that_question_ui_test's 'a pick gives
    // feedback and submits the option key', where the same tap plays
    // gameTap.
    final sounds = FakeSoundService();
    final haptics = FakeHaptics();
    await pump(
      tester,
      stored: {...seenCoach, GamePrefsNotifier.soundKey: false},
      sounds: sounds,
      haptics: haptics,
    );

    await tester.tap(find.text('THAT'));
    await tester.pump();

    // The tap landed, and the feel it still has says the feedback ran.
    expect(find.text('Lock in That'), findsOneWidget);
    expect(haptics.selectionCount, 1);
    expect(sounds.played, isEmpty);
  });

  testWidgets('with vibration switched off in settings, choosing and locking '
      'in are still', (tester) async {
    // The control is the next test, where the same taps give a selection
    // tick and a light tap.
    final sounds = FakeSoundService();
    final haptics = FakeHaptics();
    await pump(
      tester,
      stored: {...seenCoach, GamePrefsNotifier.hapticsKey: false},
      sounds: sounds,
      haptics: haptics,
    );

    await tester.tap(find.text('THAT'));
    await tester.pump();
    await tester.tap(find.text('Lock in That'));
    await tester.pump();

    // Both taps landed, and the sound they still make says the feedback ran.
    expect(sounds.played, [AppSound.gameTap, AppSound.gameAnswer]);
    expect(haptics.selectionCount, 0);
    expect(haptics.lightCount, 0);
    expect(haptics.mediumCount, 0);
  });

  testWidgets('locking in is a placement: its sound and a light tap', (
    tester,
  ) async {
    final sounds = FakeSoundService();
    final haptics = FakeHaptics();
    await pump(tester, sounds: sounds, haptics: haptics);

    await tester.tap(find.text('THIS'));
    await tester.pump();
    await tester.tap(find.text('Lock in This'));
    await tester.pump();

    expect(sounds.played, [AppSound.gameTap, AppSound.gameAnswer]);
    expect(haptics.selectionCount, 1);
    expect(haptics.lightCount, 1);
    expect(haptics.mediumCount, 0);
  });

  testWidgets('a first-time player is walked through it', (tester) async {
    await pump(tester, stored: const {});

    expect(find.text(firstStep), findsOneWidget);
    final ring = find.byKey(const ValueKey('game-coach-ring'));
    expect(ring, findsOneWidget);
    expect(
      tester.getRect(ring),
      rectMoreOrLessEquals(tabRow(tester).inflate(5)),
    );

    // The second step points at the lock button; the third at the tabs
    // again, so its bubble stays clear of them too.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Then lock it in. Ama will not see your pick until they have '
        'answered too.',
      ),
      findsOneWidget,
    );
    final lock = find.byType(ThisOrThatPrimaryAction);
    expect(lock, findsOneWidget);
    expect(
      tester.getRect(ring),
      rectMoreOrLessEquals(tester.getRect(lock).inflate(5)),
    );

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text(lastStep), findsOneWidget);
    expect(
      tester.getRect(ring),
      rectMoreOrLessEquals(tabRow(tester).inflate(5)),
    );
  });

  testWidgets('the game can be played with the tutorial still up', (
    tester,
  ) async {
    await pump(tester, stored: const {});
    expect(find.text(firstStep), findsOneWidget);

    await tester.tap(find.text('THAT'));
    await tester.pump();

    expect(find.text('Lock in That'), findsOneWidget);
    expect(find.text(firstStep), findsOneWidget);
  });

  testWidgets('How to play in settings replays the tutorial', (tester) async {
    await pump(tester);
    // The control for the step showing below.
    expect(find.text(firstStep), findsNothing);
    expect(find.text('Choose your side'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How to play'));
    await tester.pumpAndSettle();

    expect(find.byType(GameSettingsSheet), findsNothing);
    expect(find.textContaining('There are no wrong answers.'), findsNothing);
    expect(find.text(firstStep), findsOneWidget);
    expect(find.byKey(const ValueKey('game-coach-ring')), findsOneWidget);
  });

  testWidgets('the hidden-pick line names the partner', (tester) async {
    await pump(tester);

    expect(
      find.text('Your pick stays hidden until Ama has answered too.'),
      findsOneWidget,
    );
    expect(find.textContaining('both of you'), findsNothing);
  });

  testWidgets('without a name, the words say "your partner"', (tester) async {
    // 'Partner' is what the router passes when no name could be found.
    await pump(
      tester,
      stored: const {},
      screen: question(partnerName: 'Partner'),
    );

    expect(
      find.text('Your pick stays hidden until your partner has answered too.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Then lock it in. Your partner will not see your pick until they '
        'have answered too.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Partner will'), findsNothing);
    expect(find.textContaining('both of you'), findsNothing);
  });

  testWidgets('the tabs are tiles and the forward one stands proud', (
    tester,
  ) async {
    await pump(tester);

    void forwardStandsProud(String forwardLabel) {
      final tiles = tester.widgetList<GameTile>(tilesOfCard()).toList();
      expect(tiles, hasLength(3));
      final forward = tiles.where((tile) => tile.selected == true).toList();
      expect(forward, hasLength(1));
      expect(forward.single.semanticLabel, forwardLabel);
      for (final other in tiles.where((tile) => tile.selected != true)) {
        expect(forward.single.depth, greaterThan(other.depth));
      }
    }

    forwardStandsProud('OR');
    await tester.tap(find.text('THIS'));
    await tester.pumpAndSettle();
    forwardStandsProud('THIS');
  });

  testWidgets('ink on a chosen card is readable on both option colours', (
    tester,
  ) async {
    final checked = <String>[];
    for (final (tab, option) in [('THIS', 'Stay in'), ('THAT', 'Go out')]) {
      await pump(tester, screen: question(key: ValueKey(tab)));
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();

      final card = panelColour(tester);
      expect(card, isNot(GameTheme.tile), reason: 'the card did not flood');
      final ink =
          tester
              .widget<RichText>(
                find.descendant(
                  of: find.text(option),
                  matching: find.byType(RichText),
                ),
              )
              .text
              .style!
              .color!;
      expect(contrast(ink, card), greaterThanOrEqualTo(4.5), reason: tab);
      checked.add(tab);
    }
    expect(checked, ['THIS', 'THAT']);
  });

  testWidgets('every word on the card and its tabs can be read, before and '
      'after a choice', (tester) async {
    final names = <String, List<String>>{};
    for (final tab in [null, 'THIS', 'THAT']) {
      final state = tab ?? 'question';
      await pump(tester, screen: question(key: ValueKey(state)));
      if (tab != null) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
      }

      final ink = inkOnCard(tester);
      expect(ink, isNotEmpty);
      names[state] = [for (final piece in ink) piece.text];
      expect(
        ink
            .where((piece) => piece.contrast < 4.5)
            .map(
              (piece) => '${piece.text} (${piece.contrast.toStringAsFixed(2)})',
            ),
        isEmpty,
        reason: state,
      );
    }

    const asked = 'Friday night: stay in or go out?';
    expect(names['question'], unorderedEquals(['THIS', 'OR', 'THAT', asked]));
    expect(
      names['THIS'],
      unorderedEquals(['THIS', 'OR', 'THAT', asked, 'Stay in']),
    );
    expect(
      names['THAT'],
      unorderedEquals(['THIS', 'OR', 'THAT', asked, 'Go out']),
    );
  });

  for (final MapEntry(key: themeName, value: theme) in fitThemes.entries) {
    testWidgets('every tutorial step fits its bubble on a 320 px phone'
        '${fitThemeSuffix(themeName, theme)}', (tester) async {
      final shown = <String>[];
      for (final name in ['Ama', 'Partner']) {
        await pump(
          tester,
          stored: const {},
          screen: question(partnerName: name, key: ValueKey(name)),
          surface: const Size(320, 568),
          theme: theme,
        );

        for (var step = 0; step < 3; step++) {
          final bubble = find.byType(GameCoachBubble);
          expect(bubble, findsOneWidget);
          shown.add(tester.widget<GameCoachBubble>(bubble).text);

          // The words are in a scroll view that gives way when space is
          // short: fitting means it has nothing to scroll.
          final scroll = find.descendant(
            of: bubble,
            matching: find.byType(Scrollable),
          );
          expect(scroll, findsOneWidget);
          final position = tester.state<ScrollableState>(scroll).position;
          expect(position.maxScrollExtent, 0, reason: shown.last);
          expect(tester.takeException(), isNull);

          final action = step < 2 ? 'Next' : 'Got it';
          final screenRect = Offset.zero & const Size(320, 568);
          expect(
            screenRect.contains(tester.getRect(find.text(action)).bottomRight),
            isTrue,
            reason: shown.last,
          );
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
        }
        expect(find.byType(GameCoachBubble), findsNothing);
      }
      expect(shown, hasLength(6));
    });
  }

  // Phones the tutorial has to work on, with the space a notch and a home
  // bar take on a real one. The 375 x 812 phone without insets is the
  // control: 'the game can be played with the tutorial still up'.
  final phones = <String, (Size, FakeViewPadding?)>{
    '320 x 568': (const Size(320, 568), null),
    '360 x 640': (const Size(360, 640), null),
    '375 x 667': (const Size(375, 667), null),
    '375 x 812 with a notch': (
      const Size(375, 812),
      const FakeViewPadding(top: 47, bottom: 34),
    ),
  };
  for (final (themeName, theme, name, (size, padding)) in [
    for (final themed in fitThemes.entries)
      for (final sized in phones.entries)
        (themed.key, themed.value, sized.key, sized.value),
  ]) {
    for (final step in [1, 2, 3]) {
      testWidgets('on a $name phone, step $step\'s bubble covers neither what '
          'it points at nor the tabs${fitThemeSuffix(themeName, theme)}', (
        tester,
      ) async {
        await pump(
          tester,
          stored: const {},
          surface: size,
          padding: padding,
          theme: theme,
        );
        for (var next = 1; next < step; next++) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }

        final bubble = tester.getRect(find.byType(GameCoachBubble));
        final pointed =
            step == 2
                ? tester.getRect(find.byType(ThisOrThatPrimaryAction))
                : tabRow(tester);
        expect(bubble.overlaps(pointed), isFalse);
        // Whatever the step points at, the tabs stay clear: they are what
        // the player is being taught to pull.
        expect(bubble.overlaps(tabRow(tester)), isFalse);
        expect(find.byKey(const ValueKey('game-coach-ring')), findsOneWidget);

        // A missed tap fails the test: THAT has to be reachable.
        await tester.tap(find.text('THAT'));
        await tester.pump();
        expect(find.text('Lock in That'), findsOneWidget);
        expect(find.byType(GameCoachBubble), findsOneWidget);
      });
    }
  }

  // Step 2, where the bubble sits next to the lock button below the body:
  // a longer name wraps the line under the button and lengthens the step,
  // and a one-line question makes a shorter card, both of which push the
  // tabs and the bubble together on a small phone.
  final step2Cases = <(String, String)>[
    ('Ama', 'Friday night: stay in or go out?'),
    ('Kwame Mensah', 'Friday night: stay in or go out?'),
    ('Partner', 'Tea or coffee?'),
    ('Anastasia-Mariela', 'Tea or coffee?'),
  ];
  test('step 2 has cases to check', () {
    expect(step2Cases, isNotEmpty);
    expect(step2Cases.last.$1.length, 17);
  });
  for (final (themeName, theme, size) in [
    for (final themed in fitThemes.entries)
      for (final size in [
        const Size(320, 568),
        const Size(360, 640),
        const Size(375, 667),
      ])
        (themed.key, themed.value, size),
  ]) {
    for (final (partner, asked) in step2Cases) {
      testWidgets('step 2 on a ${size.width.toInt()} x ${size.height.toInt()} '
          'phone, for $partner and "$asked", keeps clear of the tabs'
          '${fitThemeSuffix(themeName, theme)}', (tester) async {
        await pump(
          tester,
          stored: const {},
          surface: size,
          screen: question(partnerName: partner, questionText: asked),
          theme: theme,
        );
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Then lock it in.'), findsOneWidget);

        final bubble = tester.getRect(find.byType(GameCoachBubble));
        expect(bubble.overlaps(tabRow(tester)), isFalse);

        await tester.tap(find.text('THAT'));
        await tester.pump();
        expect(find.text('Lock in That'), findsOneWidget);
      });
    }
  }

  testWidgets('moving to the next step never shows the bubble anywhere but '
      'where it lands', (tester) async {
    for (final size in [const Size(320, 568), phone]) {
      await pump(
        tester,
        stored: const {},
        surface: size,
        screen: question(key: ValueKey(size)),
      );
      for (var step = 2; step <= 3; step++) {
        await tester.tap(find.text('Next'));
        // Exactly one frame: what the player sees first.
        await tester.pump();
        final first = find.byType(GameCoachBubble);
        final firstRect =
            first.evaluate().isEmpty ? null : tester.getRect(first);
        if (firstRect != null) {
          expect(firstRect.overlaps(tabRow(tester)), isFalse);
        }

        await tester.pumpAndSettle();
        final settled = tester.getRect(find.byType(GameCoachBubble));
        if (firstRect != null) expect(firstRect, settled, reason: '$step');
      }
    }
  });

  testWidgets('a replay never shows the bubble anywhere but where it lands', (
    tester,
  ) async {
    for (final size in [const Size(320, 568), phone]) {
      await pump(tester, surface: size, screen: question(key: ValueKey(size)));
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Support'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('How to play'));
      await tester.pump();

      final first = find.byType(GameCoachBubble);
      final firstRect = first.evaluate().isEmpty ? null : tester.getRect(first);
      if (firstRect != null) {
        expect(firstRect.overlaps(tabRow(tester)), isFalse);
      }

      await tester.pumpAndSettle();
      expect(find.text(firstStep), findsOneWidget);
      final settled = tester.getRect(find.byType(GameCoachBubble));
      if (firstRect != null) expect(firstRect, settled);
    }
  });

  GameTile tab(WidgetTester tester, String label) => tester
      .widgetList<GameTile>(tilesOfCard())
      .singleWhere((tile) => tile.semanticLabel == label);

  testWidgets('the chosen tab rises, and the one it replaces settles back', (
    tester,
  ) async {
    await pump(tester, reduceMotion: false);
    expect(tab(tester, 'THIS').depth, 2);
    expect(tab(tester, 'OR').depth, 5);

    await tester.tap(find.text('THIS'));
    await tester.pump();
    await tester.pump(GameMotion.settle ~/ 2);

    final rising = tab(tester, 'THIS').depth;
    final settling = tab(tester, 'OR').depth;
    expect(rising, greaterThan(2));
    expect(rising, lessThan(5));
    expect(settling, greaterThan(2));
    expect(settling, lessThan(5));

    await tester.pumpAndSettle();
    expect(tab(tester, 'THIS').depth, 5);
    expect(tab(tester, 'OR').depth, 2);
  });

  testWidgets('with reduced motion the chosen tab is forward at once', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('THIS'));
    await tester.pump();

    expect(tab(tester, 'THIS').depth, 5);
    expect(tab(tester, 'OR').depth, 2);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
