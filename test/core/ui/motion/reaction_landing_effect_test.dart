import 'package:attune/core/ui/motion/reaction_landing_effect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bubble expands, compresses, and settles when trigger changes', (
    tester,
  ) async {
    var trigger = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ReactionImpactScale(
              trigger: trigger,
              child: const SizedBox(width: 120, height: 60),
            );
          },
        ),
      ),
    );

    rebuild(() => trigger++);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final impact = tester.widget<ScaleTransition>(
      find.byKey(const ValueKey('reaction-bubble-impact')),
    );
    final expanded = impact.scale.value;
    expect(expanded, greaterThan(1));

    await tester.pump(const Duration(milliseconds: 150));
    expect(impact.scale.value, lessThan(expanded));

    await tester.pumpAndSettle();
    expect(impact.scale.value, closeTo(1, 0.001));
  });

  testWidgets('expands, retracts, and removes the reaction impact overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showReactionLandingEffect(
                        context: context,
                        center: const Offset(180, 240),
                        emoji: '😂',
                      ),
                  child: const Text('land'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('land'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('reaction-landing-splash')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 90));
    final landingText = find.descendant(
      of: find.byKey(const ValueKey('reaction-landing-emoji')),
      matching: find.text('😂'),
    );
    expect(
      DefaultTextStyle.of(landingText.evaluate().single).style.decoration,
      TextDecoration.none,
    );
    final expanded = tester.widget<Transform>(
      find.byKey(const ValueKey('reaction-landing-emoji')),
    );
    expect(expanded.transform.getMaxScaleOnAxis(), greaterThan(1));

    await tester.pump(const Duration(milliseconds: 150));
    final retracted = tester.widget<Transform>(
      find.byKey(const ValueKey('reaction-landing-emoji')),
    );
    expect(
      retracted.transform.getMaxScaleOnAxis(),
      lessThan(expanded.transform.getMaxScaleOnAxis()),
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reaction-landing-emoji')), findsNothing);
  });

  testWidgets('reduced motion skips the landing overlay', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showReactionLandingEffect(
                          context: context,
                          center: const Offset(180, 240),
                          emoji: '❤️',
                        ),
                    child: const Text('land'),
                  ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('land'));
    await tester.pump();
    expect(find.byKey(const ValueKey('reaction-landing-emoji')), findsNothing);
  });
}
