import 'package:attune/features/games/presentation/widgets/round_handoff.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoundHandoff', () {
    Widget host({
      required VoidCallback onLeave,
      bool reduceMotion = false,
      Duration duration = kRoundHandoffDuration,
    }) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: RoundHandoff(
            onLeave: onLeave,
            duration: duration,
            child: const Text('Your roll is in'),
          ),
        ),
      ),
    );

    testWidgets('the result stays put before it leaves', (tester) async {
      // The whole point. Screens that popped the instant the move landed
      // swallowed the turn -- the player never saw the number they
      // rolled.
      var left = 0;
      await tester.pumpWidget(host(onLeave: () => left++));

      await tester.pump(const Duration(seconds: 3));
      expect(left, 0, reason: 'left before the player could read it');
      expect(find.text('Your roll is in'), findsOneWidget);

      await tester.pump(kRoundHandoffDuration);
      expect(left, 1);
    });

    testWidgets('a tap skips the wait', (tester) async {
      // Waiting is a floor on the experience, never a ceiling: a player
      // who has read the result says so by tapping.
      var left = 0;
      await tester.pumpWidget(host(onLeave: () => left++));

      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Your roll is in'));
      expect(left, 1);

      // And the timer that was already running must not fire a second
      // leave -- on a Navigator that is two screens popped, not one.
      await tester.pump(kRoundHandoffDuration * 2);
      expect(left, 1);
    });

    testWidgets('reduce motion still waits', (tester) async {
      // Suppressing the animation must not suppress the pause: that
      // would hand these players back the abrupt exit everyone else
      // just stopped getting.
      var left = 0;
      await tester.pumpWidget(host(onLeave: () => left++, reduceMotion: true));

      await tester.pump(const Duration(seconds: 3));
      expect(left, 0);

      await tester.pump(kRoundHandoffDuration);
      expect(left, 1);
    });

    testWidgets('it leaves exactly once', (tester) async {
      var left = 0;
      await tester.pumpWidget(host(onLeave: () => left++));
      await tester.pump(kRoundHandoffDuration * 3);
      expect(left, 1);
    });

    testWidgets('disposing cancels the wait rather than leaking it', (
      tester,
    ) async {
      // Checklist 2.10 / 2.13. An uncancelled Timer keeps the State
      // object alive until it fires. The `mounted` guard inside the
      // callback hides that from any behavioural assertion -- the timer
      // is still queued either way -- so this test deliberately never
      // pumps past the duration. A leaked timer is then still pending
      // when the test ends, and the framework fails it as such.
      var left = 0;
      await tester.pumpWidget(host(onLeave: () => left++, reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 100));

      // Replace the subtree: the handoff is disposed mid-wait.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('gone'))),
      );

      expect(left, 0, reason: 'a disposed handoff still fired');
      expect(find.text('gone'), findsOneWidget);
    });

    testWidgets('the pause is long enough to read a result', (tester) async {
      // A number the tests can point at, so a later edit that quietly
      // trims it back toward the old instant exit fails here.
      expect(kRoundHandoffDuration.inSeconds, greaterThanOrEqualTo(5));
      expect(kRoundHandoffDuration.inSeconds, lessThanOrEqualTo(10));
    });

    testWidgets('a screen reader is offered the same exit', (tester) async {
      // The tap target is the whole screen, which a screen reader cannot
      // find by feel -- so the action is published rather than implied.
      final handle = tester.ensureSemantics();
      var left = 0;
      await tester.pumpWidget(host(onLeave: () => left++));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.getSemantics(find.bySemanticsLabel('Back to chat')),
        isNotNull,
      );
      await tester.pump(kRoundHandoffDuration);
      expect(left, 1);
      handle.dispose();
    });
  });
}
