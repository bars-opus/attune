import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the community feed can open pre-filtered to one game', () {
    // The entry lived only in the games hub, which is being removed, and
    // opened unfiltered. Each game that has questions should be able to
    // show its OWN community questions rather than making the user find
    // the filter.
    final src =
        File(
          'lib/features/community/presentation/screens/community_feed_screen.dart',
        ).readAsStringSync();

    expect(
      src,
      contains('initialTypeFilter'),
      reason: 'a game opening the feed should land on its own questions',
    );
  });

  test('the games that have questions offer a community entry', () {
    // This or That, Truth or Dare and 36 Questions all draw from question
    // pools, so each should surface what other couples are asking.
    for (final path in [
      'lib/features/games/this_or_that/presentation/screens/this_or_that_games_hub_screen.dart',
      'lib/features/games/truth_or_dare/presentation/screens/truth_or_dare_tone_selector_screen.dart',
      'lib/features/games/thirty_six_questions/presentation/screens/thirty_six_journey_overview_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('CommunityQuestionsEntry'),
        reason: '$path has no community questions entry',
      );
    }
  });

  test('36 Questions is routed directly, not via the games hub', () {
    // The hub is going away, and it was the only thing standing between
    // the chat sheet and the journey.
    final src =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();

    final block = src.substring(
      src.indexOf('case ChatGameDestination.thirtySixQuestions:'),
      src.indexOf('case ChatGameDestination.mirror:'),
    );
    expect(
      block,
      isNot(contains("pushNamed('gamesHub')")),
      reason: '36 Questions should open its own journey',
    );
  });

  test('the entry passes its filter through the route', () {
    // The parameter existing proves nothing on its own: the widget has to
    // send it and the route has to read it. Either half missing leaves the
    // feed opening on "All" while every source check passes.
    final entry =
        File(
          'lib/features/community/presentation/widgets/community_questions_entry.dart',
        ).readAsStringSync();
    final router =
        File('lib/app/routing/app_router.dart').readAsStringSync();

    expect(
      entry,
      contains("'type': typeFilter!"),
      reason: 'the entry must send its filter',
    );
    expect(
      router,
      contains("state.uri.queryParameters['type']"),
      reason: 'the route must read it back',
    );
  });
}
