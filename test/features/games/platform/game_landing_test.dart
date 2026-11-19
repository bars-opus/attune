import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_landing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';

void main() {
  group('the button', () {
    test('says something in every state', () {
      for (final status in GameLandingStatus.values) {
        final action = landingAction(GameLandingState(status: status));
        expect(action.label, isNotEmpty, reason: '$status');
      }
    });

    test('reads Play, Join, Your turn and Play again when you can act', () {
      String label(GameLandingStatus s) =>
          landingAction(GameLandingState(status: s)).label;

      expect(label(GameLandingStatus.fresh), 'Play');
      expect(label(GameLandingStatus.invited), 'Join');
      expect(label(GameLandingStatus.yourTurn), 'Your turn');
      expect(label(GameLandingStatus.finished), 'Play again');
    });

    test('is only disabled while waiting on the partner', () {
      for (final status in GameLandingStatus.values) {
        expect(
          landingAction(GameLandingState(status: status)).enabled,
          status != GameLandingStatus.waiting,
          reason: '$status',
        );
      }
    });

    test('names the partner being waited for', () {
      expect(
        landingAction(
          const GameLandingState(
            status: GameLandingStatus.waiting,
            partnerName: 'Ama',
          ),
        ).label,
        'Waiting for Ama',
      );
    });

    test('falls back when the name has not loaded', () {
      for (final name in [null, '', '   ']) {
        expect(
          landingAction(
            GameLandingState(
              status: GameLandingStatus.waiting,
              partnerName: name,
            ),
          ).label,
          'Waiting for your partner',
          reason: 'name "$name"',
        );
      }
    });
  });

  group('the page', () {
    Future<void> pump(
      WidgetTester tester, {
      GameLandingState state = const GameLandingState(
        status: GameLandingStatus.fresh,
      ),
      VoidCallback? onPrimary,
      VoidCallback? onRemind,
      VoidCallback? onHowToPlay,
      double textScale = 1,
      bool withEntries = true,
    }) async {
      useSurface(tester, phone);
      await tester.pumpWidget(
        gameHost(
          GameLandingScreen(
            definition: demoGame(withEntries: withEntries),
            state: state,
            onPrimary: onPrimary,
            onRemind: onRemind,
            onHowToPlay: onHowToPlay,
          ),
          prefs: await testPrefs(),
          textScale: textScale,
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the game, its tagline and its ways to play', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Tile Tutorial'), findsOneWidget);
      expect(find.text('STARTER PACK'), findsOneWidget);
      expect(find.text('Learn how the shell fits together.'), findsOneWidget);
      expect(find.text('1. Learn the basics'), findsOneWidget);
      expect(find.text('2. Themes'), findsOneWidget);
      expect(find.text('Pick a mood'), findsOneWidget);
      expect(find.text('3. Past games'), findsOneWidget);
    });

    testWidgets('everything written on the ground can be read there', (
      tester,
    ) async {
      await pump(
        tester,
        state: const GameLandingState(
          status: GameLandingStatus.waiting,
          partnerName: 'Ama',
          caption: 'Round 3 of 10',
          canRemind: true,
        ),
        onRemind: () {},
      );

      final ink = inkOnGround(tester, of: find.byType(GameLandingScreen));
      // The title, label, tagline, caption, reminder and three entries,
      // one with a subtitle -- so the check below is checking something.
      expect(ink.length, greaterThanOrEqualTo(9));
      expect(
        ink.where((piece) => piece.contrast < 4.5).map((piece) => piece.text),
        isEmpty,
        reason: 'dark ink on the dark ground',
      );
    });

    testWidgets('pressing Play is reported', (tester) async {
      var presses = 0;
      await pump(tester, onPrimary: () => presses++);

      await tester.tap(find.byType(GamePrimaryButton));
      await tester.pump();

      expect(presses, 1);
    });

    testWidgets('the button does nothing while waiting on the partner', (
      tester,
    ) async {
      var presses = 0;
      await pump(
        tester,
        state: const GameLandingState(
          status: GameLandingStatus.waiting,
          partnerName: 'Ama',
        ),
        onPrimary: () => presses++,
      );

      expect(find.text('Waiting for Ama'), findsOneWidget);
      await tester.tap(find.byType(GamePrimaryButton), warnIfMissed: false);
      await tester.pump();

      // The control is the test above: the same tap does report when the
      // player can act.
      expect(presses, 0);
    });

    testWidgets('the caption says where the game stands', (tester) async {
      await pump(
        tester,
        state: const GameLandingState(
          status: GameLandingStatus.yourTurn,
          caption: 'Round 3 of 10',
        ),
      );

      expect(find.text('ROUND 3 OF 10'), findsOneWidget);
    });

    testWidgets('a reminder is offered only while waiting, and only when one '
        'can be sent', (tester) async {
      var reminders = 0;

      await pump(
        tester,
        state: const GameLandingState(
          status: GameLandingStatus.waiting,
          canRemind: true,
        ),
        onRemind: () => reminders++,
      );
      expect(find.text('Send a reminder'), findsOneWidget);
      await tester.tap(find.text('Send a reminder'));
      expect(reminders, 1);

      await pump(
        tester,
        state: const GameLandingState(status: GameLandingStatus.waiting),
        onRemind: () => reminders++,
      );
      expect(find.text('Send a reminder'), findsNothing);

      await pump(
        tester,
        state: const GameLandingState(
          status: GameLandingStatus.yourTurn,
          canRemind: true,
        ),
        onRemind: () => reminders++,
      );
      expect(find.text('Send a reminder'), findsNothing);
    });

    testWidgets('the help button opens how to play', (tester) async {
      var opened = 0;
      await pump(tester, onHowToPlay: () => opened++);

      await tester.tap(find.bySemanticsLabel('How to play'));

      expect(opened, 1);
    });

    testWidgets('a game with no entries shows no list', (tester) async {
      await pump(tester, withEntries: false);

      expect(find.textContaining('1. '), findsNothing);
      expect(find.text('Tile Tutorial'), findsOneWidget);
    });

    testWidgets('the largest text size scrolls instead of overflowing', (
      tester,
    ) async {
      await pump(tester, textScale: 2);

      expect(tester.takeException(), isNull);

      // Everything is still reachable: the last entry can be scrolled to.
      await tester.scrollUntilVisible(
        find.text('3. Past games'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('3. Past games'), findsOneWidget);
    });
  });
}
