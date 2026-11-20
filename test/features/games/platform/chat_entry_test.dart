import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/games/platform/legacy/legacy_game_opener.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/game_test_support.dart';
import 'support/route_recorder.dart';

void main() {
  group('openGameRoute, This or That', () {
    Future<void> pumpCard(WidgetTester tester, {String? sessionId}) async {
      useSurface(tester, phone);
      await tester.pumpWidget(
        gameRouterHost(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed:
                          () => unawaited(
                            openGameRoute(
                              context,
                              ChatGameDestination.thisOrThat,
                              relationshipId: 'r1',
                              sessionId: sessionId,
                            ),
                          ),
                      child: const Text('card'),
                    ),
                  ),
                ),
          ),
          prefs: await testPrefs(),
        ),
      );
      await tester.pump();
    }

    testWidgets('a This or That card opens that game, not a landing page', (
      tester,
    ) async {
      await pumpCard(tester, sessionId: 's1');

      await tester.tap(find.text('card'));
      await tester.pumpAndSettle();

      expect(find.text('opened:thisOrThatSessionRouter:s1'), findsOneWidget);
      expect(find.textContaining('opened:gameLanding'), findsNothing);
    });

    testWidgets('This or That with no session opens its landing page', (
      tester,
    ) async {
      await pumpCard(tester);

      await tester.tap(find.text('card'));
      await tester.pumpAndSettle();

      expect(find.text('opened:gameLanding:this_or_that'), findsOneWidget);
      expect(
        find.textContaining('opened:thisOrThatSessionRouter'),
        findsNothing,
      );
    });
  });

  test('the games button opens the hub', () {
    // The chat screen cannot be pumped in a unit test; this pins the wiring
    // the same way games_untouched_test pins the rest of it.
    final chat =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();
    final body = chat.substring(
      chat.indexOf('void _openGames() {'),
      chat.indexOf('void _toggleHeaderExpanded()'),
    );
    expect(body, contains("pushNamed('gamesHub')"));
    expect(body, isNot(contains('showChatGamesPicker(')));
  });

  group('the default legacy opener', () {
    late BuildContext home;
    late WidgetRef homeRef;

    // legacyGameOpenerProvider is NOT overridden: the real opener runs,
    // through the chat's routing switch, into the stand-in routes.
    Future<void> pumpHome(WidgetTester tester) async {
      useSurface(tester, phone);
      await tester.pumpWidget(
        gameRouterHost(
          home: Consumer(
            builder: (context, ref, _) {
              home = context;
              homeRef = ref;
              return const Scaffold(body: Center(child: Text('home')));
            },
          ),
          prefs: await testPrefs(),
          overrides: [
            currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
          ],
        ),
      );
      await tester.pump();
    }

    testWidgets('opens a This or That session on its board', (tester) async {
      await pumpHome(tester);

      await homeRef.read(legacyGameOpenerProvider)(
        home,
        'this_or_that',
        sessionId: 's1',
      );
      await tester.pumpAndSettle();

      expect(find.text('opened:thisOrThatSessionRouter:s1'), findsOneWidget);
    });

    testWidgets('a game the app cannot route opens nothing', (tester) async {
      await pumpHome(tester);

      // Never Have I Ever has a game type but no screens.
      expect(chatGameDestinationForType('never_have_i_ever'), isNull);
      await homeRef.read(legacyGameOpenerProvider)(home, 'never_have_i_ever');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('opened:'), findsNothing);
      // Positive control: the host is still showing its home screen.
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a start completes once navigation has begun', (tester) async {
      await pumpHome(tester);

      var completed = false;
      unawaited(
        homeRef
            .read(legacyGameOpenerProvider)(
              home,
              'this_or_that',
              sessionId: 's1',
            )
            .then((_) => completed = true),
      );
      await tester.pumpAndSettle();

      // The pushed game is still open -- nothing has popped it -- and the
      // start has already completed.
      expect(find.text('opened:thisOrThatSessionRouter:s1'), findsOneWidget);
      expect(completed, isTrue);

      // Back home, so nothing is left open.
      GoRouter.of(
        tester.element(find.text('opened:thisOrThatSessionRouter:s1')),
      ).pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });
  });
}
