import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart';

/// Pumps the sheet with both session lists supplied directly.
///
/// The real providers reach Supabase for the relationship id, so every
/// widget test here overrides them. gameSessionEventsProvider is
/// overridden too: it opens a realtime channel the moment the section
/// builds.
Widget _sheet({
  required ValueChanged<ChatGameDestination> onSelect,
  List<Map<String, dynamic>> active = const [],
  List<Map<String, dynamic>> recent = const [],
}) {
  return ProviderScope(
    overrides: [
      activeGamesProvider.overrideWith((ref) async => active),
      recentGamesProvider.overrideWith((ref) async => recent),
      gameSessionEventsProvider.overrideWith((ref) => const Stream.empty()),
    ],
    child: withScreenUtil(
      MaterialApp(home: Scaffold(body: ChatGamesSheet(onSelect: onSelect))),
    ),
  );
}

void main() {
  test('every launchable destination is reachable from the catalogue', () {
    // The catalogue is a const list, so a destination added to the enum
    // without a matching entry is invisible in the UI with no compile
    // error. This is the guard against that.
    //
    // Every enum value is now a game: the gamesHub "see all" destination
    // is gone with the hub, so nothing is exempt from this.
    final reachable = chatGameDestinationsInCatalogue();
    for (final destination in ChatGameDestination.values) {
      expect(
        reachable.contains(destination),
        isTrue,
        reason: '$destination has no entry in _chatGameCategories',
      );
    }
  });

  test('the three session games are present', () {
    final reachable = chatGameDestinationsInCatalogue();
    expect(reachable, contains(ChatGameDestination.mirror));
    expect(reachable, contains(ChatGameDestination.slidingScale));
    expect(reachable, contains(ChatGameDestination.scenario));
  });

  test('an unbuilt game is marked coming soon, not silently routed', () {
    // Never Have I Ever is listed with a title, subtitle and icon but has
    // no implementation, no spec and no route. It used to push the games
    // hub, which did not offer it either — a user picked a game and
    // arrived somewhere unrelated with no explanation.
    expect(
      chatGameDestinationsComingSoon(),
      contains(ChatGameDestination.neverHaveIEver),
      reason: 'a game with no implementation must not read as playable',
    );
  });

  test('every game that is NOT coming soon is genuinely reachable', () {
    // The guard that matters: this list must shrink as games ship, and
    // must never be used to hide a game that simply broke.
    final comingSoon = chatGameDestinationsComingSoon();
    for (final destination in ChatGameDestination.values) {
      if (comingSoon.contains(destination)) continue;
      expect(
        chatGameDestinationsInCatalogue(),
        contains(destination),
        reason: '$destination is offered as playable but has no entry',
      );
    }
  });

  testWidgets('a coming-soon row is inert and labelled', (tester) async {
    // Asserted on the rendered row rather than by tapping: the sheet is a
    // lazy scroller inside a search-filtered list, and driving it to the
    // right offset tests the scroll physics more than the behaviour. What
    // must hold is that the row carries the label and refuses its tap.
    ChatGameDestination? selected;

    await tester.pumpWidget(_sheet(onSelect: (d) => selected = d));

    // Narrow the list to the one game, so it is built.
    await tester.enterText(find.byType(TextField).first, 'Never Have');
    await tester.pumpAndSettle();

    expect(find.text('Never Have I Ever'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);

    await tester.tap(find.text('Never Have I Ever'), warnIfMissed: false);
    await tester.pump();

    expect(
      selected,
      isNull,
      reason: 'a coming-soon row must not launch anything',
    );
  });

  testWidgets('a built game still selects', (tester) async {
    // The inverse, so "nothing is tappable" cannot pass the test above.
    ChatGameDestination? selected;

    await tester.pumpWidget(_sheet(onSelect: (d) => selected = d));

    // Searched by subtitle: typing the title puts it in the search field
    // too, and find.text would then match the input as well as the row.
    await tester.enterText(find.byType(TextField).first, 'color battle');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Paint Ball'), warnIfMissed: false);
    await tester.pump();

    expect(selected, ChatGameDestination.paintBall);
  });

  testWidgets('an active game is listed and resumes on tap', (tester) async {
    // The games hub listed active games in a Container with no tap
    // handler at all, so the hub's main list was decorative: the only way
    // back into a game in progress was the original chat invite. Moving
    // the list here is also the fix for that.
    ChatGameDestination? selected;

    await tester.pumpWidget(
      _sheet(
        onSelect: (d) => selected = d,
        active: const [
          {
            'id': 'a1',
            'game_type': 'mirror',
            'game_type_display': 'Mirror',
            'status': 'active',
          },
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue playing'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);

    // Scoped to the session row: the catalogue below lists a 'Mirror'
    // entry too, and tapping that one would start a game rather than
    // resume this one — the exact confusion this test has to rule out.
    final row = find.ancestor(
      of: find.text('In progress'),
      matching: find.byType(CardInkWell),
    );
    expect(
      find.descendant(of: row, matching: find.text('Mirror')),
      findsOneWidget,
    );

    await tester.tap(row, warnIfMissed: false);
    await tester.pump();

    expect(selected, ChatGameDestination.mirror);
  });

  testWidgets('a completed game is shown but is not tappable', (tester) async {
    // A finished session is a record, not a destination. Tapping one must
    // not fire onSelect: routing to the game would resume or restart it,
    // which is not what "Recently played" offers.
    ChatGameDestination? selected;

    await tester.pumpWidget(
      _sheet(
        onSelect: (d) => selected = d,
        recent: const [
          {'id': 'r1', 'game_type': 'scenario', 'status': 'completed'},
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recently played'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);

    final row = find.ancestor(
      of: find.text('Completed'),
      matching: find.byType(CardInkWell),
    );
    // Falls back to the display-name helper: recentGamesProvider returns
    // raw table rows, with no game_type_display on them.
    expect(
      find.descendant(of: row, matching: find.text('Scenario')),
      findsOneWidget,
    );

    await tester.tap(row, warnIfMissed: false);
    await tester.pump();

    expect(selected, isNull);
  });

  testWidgets('neither section appears when both lists are empty', (
    tester,
  ) async {
    // A sheet has less room than a screen. A first-time player opening it
    // to pick a game should not meet two empty-state boxes first.
    await tester.pumpWidget(_sheet(onSelect: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('Continue playing'), findsNothing);
    expect(find.text('Recently played'), findsNothing);
  });

  testWidgets('searching hides the in-progress section', (tester) async {
    // A query filters the catalogue; a game that merely happens to be in
    // progress would otherwise survive it as a result nobody searched for.
    await tester.pumpWidget(
      _sheet(
        onSelect: (_) {},
        active: const [
          {
            'id': 'a1',
            'game_type': 'mirror',
            'game_type_display': 'Mirror',
            'status': 'active',
          },
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue playing'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'paint');
    await tester.pumpAndSettle();

    expect(find.text('Continue playing'), findsNothing);
  });

  test('every game_type that can reach game_sessions resumes somewhere', () {
    // gameTypeDisplayName is the list of types that actually land in the
    // table. Each one needs a destination, or its card renders as a
    // dead row in the list the user opened to get back into a game.
    const types = [
      'this_or_that',
      'truth_or_dare',
      '36_questions',
      'mirror',
      'sliding_scale',
      'scenario',
      'love_map',
      'paint_ball',
    ];

    for (final type in types) {
      expect(
        chatGameDestinationForType(type),
        isNotNull,
        reason: '$type has no destination, so its active card would be dead',
      );
    }

    // An unknown type must degrade to a non-tappable row, never to a
    // route name that does not exist.
    expect(chatGameDestinationForType('not_a_game'), isNull);
  });
}
