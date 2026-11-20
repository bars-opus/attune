import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/session_history_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_custom_create_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_custom_list_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/waiting_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../platform/support/game_test_support.dart';
import '../platform/support/ink_on_ground.dart';
import 'support/shell_screens.dart';
import 'support/this_or_that_fakes.dart';

/// This or That's screens, in the games shell.
///
/// Every host here is a LIGHT app: the games are dark whatever the app is
/// doing, and a light app is where a screen that forgot that shows it.
void main() {
  // Real glyph widths: the test font's square glyphs overflow a popup menu
  // row ('Hide from my view') that fits with the real font.
  setUpAll(loadGameTestFonts);

  /// [child] in the shell's host, with the screen's own providers on top.
  Future<Widget> host(
    Widget child, {
    List<Override> overrides = const [],
  }) async {
    return gameHost(
      child,
      prefs: await testPrefs(),
      reduceMotion: true,
      overrides: overrides,
    );
  }

  /// [screen] pushed over a host page, so leaving it has somewhere to go.
  Widget pushedOverHost(Widget screen) => Builder(
    builder:
        (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed:
                  () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('host'),
            ),
          ),
        ),
  );

  WaitingScreen waiting() => const WaitingScreen(
    sessionId: 'session-1',
    roundId: 'round-3',
    questionText: 'Stay in or go out?',
    userChoice: 'a',
    userChoiceText: 'Stay in',
    userChoiceEmoji: '',
    optionA: 'Stay in',
    optionB: 'Go out',
    roundNumber: 3,
    totalRounds: 10,
    isPartnerA: true,
    partnerName: 'Ama',
  );

  List<Override> waitingOverrides() => [
    thisOrThatRepositoryProvider.overrideWithValue(MockThisOrThatRepository()),
    currentUserIdProvider.overrideWithValue('user-a'),
  ];

  /// The colour a dialog or sheet is actually drawn in: its own Material.
  Color surfaceOf(WidgetTester tester, Finder of) {
    final materials = find.descendant(of: of, matching: find.byType(Material));
    expect(materials, findsWidgets);
    return tester.widget<Material>(materials.first).color!;
  }

  Color inkOf(WidgetTester tester, String text) =>
      tester
          .widget<RichText>(
            find.descendant(
              of: find.text(text),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!
          .color!;

  testWidgets('the palette is the same in a light app and a dark one', (
    tester,
  ) async {
    useSurface(tester, phone);
    final seen = <Brightness, ThisOrThatPalette>{};
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              seen[theme.brightness] = ThisOrThatPalette.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
    }

    expect(seen.keys, [Brightness.light, Brightness.dark]);
    for (final palette in seen.values) {
      expect(palette.canvas, GameTheme.ground);
      expect(palette.panel, GameTheme.raised);
      expect(palette.ink, GameTheme.onGround);
      expect(palette.mutedInk, GameTheme.mutedOnGround);
      expect(palette.line, GameTheme.hairline);
      expect(palette.thisColor, const Color(0xFFFF8A76));
      expect(palette.thatColor, const Color(0xFF8DA7FF));
      expect(palette.thisSurface, const Color(0xFF3A2424));
      expect(palette.thatSurface, const Color(0xFF202B46));
    }
  });

  testWidgets('with a round, the header reads the round over the game\'s '
      'name', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      await host(
        const ThisOrThatGameScaffold(
          roundNumber: 3,
          totalRounds: 10,
          child: SizedBox(),
        ),
      ),
    );

    expect(find.text('Round 3 of 10'), findsOneWidget);
    expect(find.text('This or That'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('This or That')).dy,
      lessThan(tester.getTopLeft(find.text('Round 3 of 10')).dy),
    );
  });

  testWidgets('without a round, the header is the screen\'s title alone', (
    tester,
  ) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      await host(
        const ThisOrThatGameScaffold(title: 'Past games', child: SizedBox()),
      ),
    );

    expect(find.text('Past games'), findsOneWidget);
    // Control: the default title is what a round would show over it.
    expect(find.text('This or That'), findsNothing);
    expect(find.textContaining('Round'), findsNothing);
  });

  testWidgets('the gear opens settings with sound and vibration, and no '
      'Leave game', (tester) async {
    // The control for 'Leave game' findsNothing is phase 1's settings test
    // ('Support offers only what the caller can act on'), where passing
    // onLeaveGame shows it.
    useSurface(tester, phone);
    await tester.pumpWidget(
      await host(const ThisOrThatGameScaffold(child: SizedBox())),
    );

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Sound effects'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    expect(find.text('How to play'), findsOneWidget);
    expect(find.text('Leave game'), findsNothing);

    // Without an onHowToPlay of its own, the game's rules open.
    await tester.tap(find.text('How to play'));
    await tester.pumpAndSettle();
    expect(find.textContaining('There are no wrong answers.'), findsOneWidget);
  });

  testWidgets('a screen\'s own How to play replaces the rules sheet', (
    tester,
  ) async {
    useSurface(tester, phone);
    var asked = 0;
    await tester.pumpWidget(
      await host(
        ThisOrThatGameScaffold(
          onHowToPlay: () => asked++,
          child: const SizedBox(),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How to play'));
    await tester.pumpAndSettle();

    expect(asked, 1);
    expect(find.textContaining('There are no wrong answers.'), findsNothing);
  });

  testWidgets('the primary action shows progress while loading and takes no '
      'taps', (tester) async {
    useSurface(tester, phone);
    var taps = 0;
    Future<void> pump({required bool loading}) async {
      await tester.pumpWidget(
        await host(
          Scaffold(
            body: Center(
              child: ThisOrThatPrimaryAction(
                label: 'Add to my deck',
                loading: loading,
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      );
    }

    // The control: not loading, a tap counts and there is no ring.
    await pump(loading: false);
    expect(find.byType(GamePrimaryButton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Add to my deck'));
    expect(taps, 1);

    await pump(loading: true);
    expect(
      tester.widget<GamePrimaryButton>(find.byType(GamePrimaryButton)).busy,
      isTrue,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Add to my deck'));
    expect(taps, 1);
  });

  testWidgets('everything written on the ground can be read, in a light app '
      'too', (tester) async {
    await pumpShellScreen(tester, thisOrThatShellScreens()['deck_list']!);

    final ink = inkOnGround(
      tester,
      of: find.byType(ThisOrThatCustomListScreen),
    );
    final texts = ink.map((piece) => piece.text).toList();
    expect(texts, contains('Our question decks'));
    expect(texts, contains(deckQuestion.questionText));
    expect(texts, contains('Played 3 times'));

    // The chosen tab's label is drawn on the tab's white pill, not on the
    // ground, and is judged against the pill instead.
    final palette = ThisOrThatPalette.of(
      tester.element(find.byType(ThisOrThatCustomListScreen)),
    );
    expect(texts, contains('Mine'));
    expect(contrast(inkOf(tester, 'Mine'), palette.ink), greaterThan(4.5));
    expect(
      ink
          .where((piece) => piece.text != 'Mine' && piece.contrast < 4.5)
          .map(
            (piece) => '${piece.text} (${piece.contrast.toStringAsFixed(2)})',
          ),
      isEmpty,
    );
  });

  testWidgets('leaving the waiting screen still asks first', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      await host(pushedOverHost(waiting()), overrides: waitingOverrides()),
    );
    await tester.tap(find.text('host'));
    await tester.pumpAndSettle();
    expect(find.text('host'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Leave for now?'), findsOneWidget);

    await tester.tap(find.text('Keep waiting'));
    await tester.pumpAndSettle();
    expect(find.text('Leave for now?'), findsNothing);
    expect(find.byType(WaitingScreen), findsOneWidget);
    expect(find.text('host'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave game'));
    await tester.pumpAndSettle();
    expect(find.byType(WaitingScreen), findsNothing);
    expect(find.text('host'), findsOneWidget);
  });

  testWidgets('"Leave for now?" is dark in a light app', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      await host(waiting(), overrides: waitingOverrides()),
    );
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(Theme.of(tester.element(dialog)).brightness, Brightness.dark);
    final surface = surfaceOf(tester, dialog);
    expect(surface.computeLuminance(), lessThan(0.05));
    expect(
      contrast(inkOf(tester, 'Leave for now?'), surface),
      greaterThan(4.5),
    );
  });

  testWidgets('the emoji sheet is dark in a light app', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(await host(const ThisOrThatCustomCreateScreen()));
    await tester.pump();

    final pickers = find.byTooltip('Choose an emoji');
    expect(pickers, findsWidgets);
    await tester.tap(pickers.first);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Give this choice a face'))).brightness,
      Brightness.dark,
    );
    final surface = surfaceOf(tester, sheet);
    expect(surface.computeLuminance(), lessThan(0.05));
    expect(
      contrast(inkOf(tester, 'Give this choice a face'), surface),
      greaterThan(4.5),
    );
  });

  testWidgets('"Hide this game?" is dark in a light app', (tester) async {
    useSurface(tester, phone);
    final session = ThisOrThatSession(
      id: 'done-1',
      relationshipId: 'rel-1',
      initiatorId: 'user-a',
      tone: 'playful',
      status: 'completed',
      totalRounds: 10,
      currentRound: 10,
      matchCount: 7,
      totalRoundsCompleted: 10,
      createdAt: DateTime(2026, 11, 2),
    );
    await tester.pumpWidget(
      await host(
        const SessionHistoryScreen(),
        overrides: [
          completedSessionsProvider.overrideWith((_) async => [session]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Game options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide from my view'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(Theme.of(tester.element(dialog)).brightness, Brightness.dark);
    final surface = surfaceOf(tester, dialog);
    expect(surface.computeLuminance(), lessThan(0.05));
    expect(
      contrast(inkOf(tester, 'Hide this game?'), surface),
      greaterThan(4.5),
    );
  });

  testWidgets('the next-card chooser\'s error can be read, in a light app', (
    tester,
  ) async {
    final repository = MockThisOrThatRepository();
    when(
      () => repository.prepareNextRound(
        sessionId: any(named: 'sessionId'),
        roundNumber: any(named: 'roundNumber'),
        source: any(named: 'source'),
        customOwnerId: any(named: 'customOwnerId'),
      ),
    ).thenThrow(Exception('offline'));
    final screen = thisOrThatShellScreens()['next_card']!;
    // With motion: the error's AnimatedSize asserts when reduced motion
    // makes its duration zero, which is the screen's own matter, not this
    // test's.
    await pumpShellScreen(tester, (
      build: screen.build,
      overrides:
          () => [
            ...screen.overrides(),
            thisOrThatRepositoryProvider.overrideWithValue(repository),
          ],
      then: null,
    ), reduceMotion: false);

    await tester.tap(find.text('Preset deck'));
    await tester.pumpAndSettle();

    const error = 'The next card could not be prepared. Try once more.';
    expect(find.text(error), findsOneWidget);
    expect(contrast(inkOf(tester, error), GameTheme.ground), greaterThan(4.5));
  });

  testWidgets('the invitation\'s error can be read, in a light app', (
    tester,
  ) async {
    final repository = MockThisOrThatRepository();
    when(
      () => repository.acceptSession(
        sessionId: any(named: 'sessionId'),
        userId: any(named: 'userId'),
        intimateConsent: any(named: 'intimateConsent'),
        fallbackTone: any(named: 'fallbackTone'),
      ),
    ).thenThrow(Exception('offline'));
    final screen = thisOrThatShellScreens()['invitation']!;
    await pumpShellScreen(tester, (
      build: screen.build,
      overrides:
          () => [
            ...screen.overrides(),
            thisOrThatRepositoryProvider.overrideWithValue(repository),
          ],
      then: null,
    ));

    await tester.tap(find.text("Let's play"));
    await tester.pumpAndSettle();

    const error =
        'That did not go through. Check your connection and try again.';
    expect(find.text(error), findsOneWidget);
    expect(contrast(inkOf(tester, error), GameTheme.ground), greaterThan(4.5));
  });

  // The question screen's pictures carry what the device remembers (the
  // tutorial seen or not) and the phone they are taken on.
  final screens = {
    for (final MapEntry(key: name, value: screen)
        in thisOrThatShellScreens().entries)
      name: (screen: screen, stored: const <String, Object>{}, size: phone),
    ...thisOrThatQuestionScreens(),
    ...thisOrThatSmallScreens(),
  };
  test('the screens below have something to check', () {
    expect(screens, isNotEmpty);
    expect(
      screens.keys,
      containsAll(['question', 'question_this', 'reveal_small']),
    );
  });
  for (final MapEntry(key: name, value: shot) in screens.entries) {
    testWidgets('$name: every word in the body can be read where it sits, '
        'on the orange or the ground', (tester) async {
      await pumpShellScreen(
        tester,
        shot.screen,
        stored: shot.stored,
        size: shot.size,
      );

      final ink = inkOnBackdrop(tester);
      expect(ink, isNotEmpty);
      // The control: the first words under the header sit high enough to
      // be on the orange, where the ground's contrast would not hold.
      final height = shot.size.height;
      expect(
        backdropAt(0, height).computeLuminance(),
        greaterThan(GameTheme.ground.computeLuminance() * 10),
      );
      expect(
        ink
            .where((piece) => piece.contrast < piece.needed)
            .map(
              (piece) => '${piece.text} (${piece.contrast.toStringAsFixed(2)})',
            ),
        isEmpty,
      );
    });
  }
}
