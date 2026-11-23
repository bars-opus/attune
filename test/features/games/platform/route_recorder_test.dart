import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/game_test_support.dart';
import 'support/route_recorder.dart';

void main() {
  late BuildContext home;

  Future<void> pumpHost(WidgetTester tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameRouterHost(
        home: Builder(
          builder: (context) {
            home = context;
            return const Scaffold(body: Text('home'));
          },
        ),
        prefs: await testPrefs(),
      ),
    );
    await tester.pump();
  }

  testWidgets('home is where it starts', (tester) async {
    await pumpHost(tester);

    expect(find.text('home'), findsOneWidget);
    expect(find.textContaining('opened:'), findsNothing);
  });

  testWidgets('a game landing names its game from the path', (tester) async {
    await pumpHost(tester);

    home.pushNamed('gameLanding', pathParameters: {'gameType': 'word_hunt'});
    await tester.pumpAndSettle();

    expect(find.text('opened:gameLanding:word_hunt'), findsOneWidget);
  });

  testWidgets('the community feed names its type from the query', (
    tester,
  ) async {
    await pumpHost(tester);

    home.pushNamed('communityFeed', queryParameters: {'type': 'this_or_that'});
    await tester.pumpAndSettle();

    expect(find.text('opened:communityFeed:this_or_that'), findsOneWidget);
  });

  testWidgets('the other stand-ins name what they were handed', (tester) async {
    await pumpHost(tester);

    const byExtra = [
      'gamesHub',
      'thisOrThatSessionRouter',
      'thisOrThatCustomList',
      'thisOrThatSessionHistory',
    ];
    // Every name the host offers is covered by this test or the two above.
    expect({
      ...byExtra,
      'gameLanding',
      'communityFeed',
    }, standInRouteNames.toSet());
    for (final name in byExtra) {
      home.pushNamed(name, extra: 'session-1');
      await tester.pumpAndSettle();
      expect(find.text('opened:$name:session-1'), findsOneWidget);

      // And back again, through the stand-in's own Back button.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget, reason: name);
      expect(find.textContaining('opened:'), findsNothing, reason: name);
    }

    home.pushNamed('gamesHub');
    await tester.pumpAndSettle();
    expect(find.text('opened:gamesHub:'), findsOneWidget);
  });
}
