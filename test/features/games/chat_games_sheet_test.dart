import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart';

void main() {
  test('every launchable destination is reachable from the catalogue', () {
    // The catalogue is a const list, so a destination added to the enum
    // without a matching entry is invisible in the UI with no compile
    // error. This is the guard against that.
    //
    // gamesHub is excluded because it is not a game: it is the "see all"
    // destination the sheet itself routes to, so it correctly has no
    // catalogue entry. Verified against the current file — every other
    // enum value does have one.
    final reachable = chatGameDestinationsInCatalogue();
    final launchable = ChatGameDestination.values.where(
      (d) => d != ChatGameDestination.gamesHub,
    );
    for (final destination in launchable) {
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
    // no implementation, no spec and no route: tapping it pushed the games
    // hub, which does not offer it either. A user picked a game and
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
      if (destination == ChatGameDestination.gamesHub) continue;
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

    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(body: ChatGamesSheet(onSelect: (d) => selected = d)),
        ),
      ),
    );

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

    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(body: ChatGamesSheet(onSelect: (d) => selected = d)),
        ),
      ),
    );

    // Searched by subtitle: typing the title puts it in the search field
    // too, and find.text would then match the input as well as the row.
    await tester.enterText(find.byType(TextField).first, 'color battle');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Paint Ball'), warnIfMissed: false);
    await tester.pump();

    expect(selected, ChatGameDestination.paintBall);
  });
}
