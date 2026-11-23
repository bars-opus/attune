import 'dart:async';
import 'dart:io';

import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_landing_page.dart';
import 'package:attune/features/games/platform/shell/games_hub_screen.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart'
    as hub;
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/domain/this_or_that_tones.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../this_or_that/support/shell_screens.dart';
import '../this_or_that/support/this_or_that_fakes.dart';
import 'support/game_test_support.dart';
import 'support/route_recorder.dart';

/// Pictures of the games hub and the landing pages, on a phone, a large
/// phone and a tablet: the screens the owner opens first.
///
/// These are for looking at. Open the PNGs when they are regenerated: a
/// golden only ever compared to itself proves the screen did not change,
/// not that it was ever right.
void main() {
  // Once for the file: loading the fonts inside each test has hung a file.
  setUpAll(loadGameTestFonts);

  // Text is drawn slightly differently on each operating system, so these
  // are compared where they are made. What a machine can check -- ink,
  // layout, overflow -- has its own test that runs everywhere.
  final comparedHere = Platform.isMacOS;

  GameCardState card({
    required String gameType,
    String? turn,
    bool? viewerAnswered,
    bool? partnerAnswered,
  }) => GameCardState(
    gameType: gameType,
    status: 'active',
    currentTurnUserId: turn,
    winnerUserId: null,
    currentRound: 3,
    totalRounds: 10,
    viewerAnswered: viewerAnswered,
    partnerAnswered: partnerAnswered,
  );

  /// Everything the hub and the landing pages read, answered: [rows] are
  /// the games in progress, [cards] where each stands, [session] This or
  /// That's game (a never-finishing read when [loading]).
  List<Override> overrides({
    List<Map<String, dynamic>> rows = const [],
    Map<String, GameCardState?> cards = const {},
    ThisOrThatSession? session,
    bool loading = false,
    List<GameRound> rounds = const [],
  }) => [
    hub.currentUserIdProvider.overrideWithValue('user-a'),
    currentUserIdProvider.overrideWithValue('user-a'),
    hub.activeGamesProvider.overrideWith((ref) async => rows),
    hub.recentGamesProvider.overrideWith((ref) async => const []),
    hub.gameSessionEventsProvider.overrideWith(
      (ref) => const Stream<void>.empty(),
    ),
    gameCardProvider.overrideWith((ref, id) => Stream.value(cards[id])),
    gamePartnerNameProvider.overrideWith((ref) async => 'Ama'),
    activeThisOrThatSessionProvider.overrideWith(
      (ref) => loading ? Completer<ThisOrThatSession?>().future : session,
    ),
    relationshipMembersProvider.overrideWith(
      (ref, id) async => (userA: 'user-a', userB: 'user-b'),
    ),
    sessionRoundsProvider.overrideWith((ref, id) async => rounds),
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    required Size size,
    required List<Override> overrides,
    ThemeData? theme,
  }) async {
    useSurface(tester, size);
    await tester.pumpWidget(
      gameRouterHost(
        home: home,
        prefs: await testPrefs(),
        overrides: overrides,
        theme: theme,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> expectPicture(WidgetTester tester, String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );

  /// The hub with Truth or Dare on your turn and This or That waiting on
  /// Ama.
  List<Override> twoInPlay() => overrides(
    rows: [
      {'id': 's1', 'game_type': 'truth_or_dare', 'initiator_id': 'user-a'},
      {'id': 's2', 'game_type': 'this_or_that', 'initiator_id': 'user-a'},
    ],
    cards: {
      's1': card(gameType: 'truth_or_dare', turn: 'user-a'),
      's2': card(
        gameType: 'this_or_that',
        viewerAnswered: true,
        partnerAnswered: false,
      ),
    },
  );

  /// This or That's round 3, Ama still to answer it; you answered three
  /// hours ago, so a reminder can go.
  List<Override> waitingWithReminder() => overrides(
    session: thisOrThatSession(),
    cards: {
      's1': card(
        gameType: 'this_or_that',
        viewerAnswered: true,
        partnerAnswered: false,
      ),
    },
    rounds: [
      GameRound(
        id: 'r3',
        sessionId: 's1',
        roundNumber: 3,
        hasAnswerA: true,
        hasAnswerB: false,
        answerASubmittedAt: DateTime.now().subtract(const Duration(hours: 3)),
        bothAnswered: false,
      ),
    ],
  );

  final shots = <
    String,
    ({
      Widget Function() home,
      List<Override> Function() overrides,
      void Function(WidgetTester tester) check,
    })
  >{
    'hub_empty': (
      home: () => const GamesHubScreen(),
      overrides: overrides,
      check: (tester) {
        expect(find.text('Play with Ama'), findsOneWidget);
        // The control for In play is hub_in_play.
        expect(find.text('In play'), findsNothing);
      },
    ),
    'hub_in_play': (
      home: () => const GamesHubScreen(),
      overrides: twoInPlay,
      check: (tester) {
        expect(find.text('In play'), findsOneWidget);
        expect(find.text('Your turn'), findsOneWidget);
        expect(find.text('Waiting for Ama'), findsOneWidget);
      },
    ),
    'landing_this_or_that_fresh': (
      home: () => const GameLandingPage(gameType: 'this_or_that'),
      overrides: overrides,
      check: (tester) {
        expect(thisOrThatTones, hasLength(5));
        expect(find.text('Play'), findsOneWidget);
        // The first tone's row is in view; the rest are below it.
        expect(
          find.textContaining(thisOrThatTones.first.label),
          findsOneWidget,
        );
      },
    ),
    'landing_this_or_that_your_turn': (
      home: () => const GameLandingPage(gameType: 'this_or_that'),
      overrides:
          () => overrides(
            session: thisOrThatSession(),
            cards: {'s1': card(gameType: 'this_or_that')},
          ),
      check: (tester) {
        expect(find.text('Your turn'), findsOneWidget);
        // GameStrings.roundOf, drawn in capitals under the button.
        expect(find.text('ROUND 3 OF 10'), findsOneWidget);
        // A game under way: no tone starts a second one.
        expect(find.textContaining(thisOrThatTones.first.label), findsNothing);
      },
    ),
    'landing_this_or_that_waiting': (
      home: () => const GameLandingPage(gameType: 'this_or_that'),
      overrides: waitingWithReminder,
      check: (tester) {
        expect(find.text('Waiting for Ama'), findsOneWidget);
        expect(find.text('ROUND 3 OF 10'), findsOneWidget);
        expect(
          find.widgetWithText(GameSecondaryButton, 'Send a reminder'),
          findsOneWidget,
        );
      },
    ),
  };

  for (final MapEntry(key: name, value: shot) in shots.entries) {
    for (final MapEntry(key: surface, value: size) in goldenSurfaces.entries) {
      testWidgets('$name on a $surface', (tester) async {
        await pump(
          tester,
          shot.home(),
          size: size,
          overrides: shot.overrides(),
        );
        shot.check(tester);

        await expectPicture(tester, '$name.$surface');
      }, skip: !comparedHere);
    }
  }

  final phoneShots = <
    String,
    ({
      Widget Function() home,
      List<Override> Function() overrides,
      void Function(WidgetTester tester) check,
    })
  >{
    'landing_truth_or_dare': (
      home: () => const GameLandingPage(gameType: 'truth_or_dare'),
      overrides: overrides,
      check: (tester) {
        expect(find.text('Truth or Dare'), findsOneWidget);
        expect(find.text('Play'), findsOneWidget);
      },
    ),
    'landing_coming_soon': (
      home: () => const GameLandingPage(gameType: 'mirror'),
      overrides: overrides,
      check: (tester) {
        final play = tester.widget<GamePrimaryButton>(
          find.byType(GamePrimaryButton),
        );
        expect(play.label, 'Coming soon');
        expect(play.onTap, isNull);
      },
    ),
    'landing_unknown': (
      home: () => const GameLandingPage(gameType: 'brand_new_game'),
      overrides: overrides,
      check: (tester) {
        expect(find.textContaining('not available'), findsOneWidget);
      },
    ),
    'landing_this_or_that_loading': (
      home: () => const GameLandingPage(gameType: 'this_or_that'),
      overrides: () => overrides(loading: true),
      check: (tester) {
        final play = tester.widget<GamePrimaryButton>(
          find.byType(GamePrimaryButton),
        );
        // Says what it will most likely say, with its icon, and cannot
        // be pressed until the state arrives.
        expect(play.label, 'Play');
        expect(play.icon, Icons.play_arrow_rounded);
        expect(play.onTap, isNull);
        expect(
          find.descendant(
            of: find.byType(GamePrimaryButton),
            matching: find.byIcon(Icons.play_arrow_rounded),
          ),
          findsOneWidget,
        );
      },
    ),
  };

  for (final MapEntry(key: name, value: shot) in phoneShots.entries) {
    testWidgets('$name on a phone', (tester) async {
      await pump(tester, shot.home(), size: phone, overrides: shot.overrides());
      shot.check(tester);

      await expectPicture(tester, '$name.phone');
    }, skip: !comparedHere);
  }

  testWidgets('the settings sheet, sound off, on a phone', (tester) async {
    // This or That's own gear, on a device where sound was switched off.
    final question = thisOrThatQuestionScreens()['question']!;
    await pumpShellScreen(
      tester,
      question.screen,
      stored: {...question.stored, GamePrefsNotifier.soundKey: false},
    );
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, hasLength(2));
    // Sound off, vibration on: one of each, so both looks are in the frame.
    expect(switches.map((s) => s.value), unorderedEquals([false, true]));

    await expectPicture(tester, 'settings_sound_off.phone');
  }, skip: !comparedHere);

  // Under the app's own light theme, as it ships: the dark games hold
  // inside a light app.
  final appLight = fitThemes['app light theme'];
  for (final name in ['hub_in_play', 'landing_this_or_that_fresh']) {
    testWidgets('$name on a phone, under the app light theme', (tester) async {
      expect(appLight, isNotNull);
      final shot = shots[name]!;
      await pump(
        tester,
        shot.home(),
        size: phone,
        overrides: shot.overrides(),
        theme: appLight,
      );
      shot.check(tester);

      await expectPicture(tester, '$name.app_light.phone');
    }, skip: !comparedHere);
  }
}
