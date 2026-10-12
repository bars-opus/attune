import 'package:attune/core/ui/neon/light_well.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every BoxDecoration painted anywhere under the test's root, so the
/// assertions read what was actually drawn rather than constructor args.
List<BoxDecoration> _paintedDecorations(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((widget) => widget.decoration)
    .whereType<BoxDecoration>()
    .toList();

void main() {
  testWidgets('the ground is painted even with nothing on it', (tester) async {
    // The field's ground is tier 1 of §2.1: it receives light and emits
    // none. An unpainted ground would fall through to the app theme,
    // which in light mode is white -- and every neon colour was chosen
    // against near-black.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LightWell())),
    );
    await tester.pump();

    final well = tester.widget<LightWell>(find.byType(LightWell));
    expect(well.tint, isNull);
    expect(tester.takeException(), isNull);

    final decorations = _paintedDecorations(tester);
    expect(
      decorations,
      isNotEmpty,
      reason: 'a positive control: without this the rest asserts nothing',
    );
    expect(
      decorations.any((d) => d.color == NeonTokens.groundColor),
      isTrue,
      reason: 'the ground must be painted with groundColor',
    );
    expect(
      decorations.any((d) => d.gradient != null),
      isTrue,
      reason: 'the default tier draws the light well falloff',
    );
  });

  testWidgets('a child renders over the ground, not under it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LightWell(child: Text('on the field')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('on the field'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the plain tier still paints the ground', (tester) async {
    // Degrading may drop the falloff, never the ground itself. A
    // transparent ground on a low-end device would be the worst
    // possible failure: the one place the tiering must not break.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NeonQualityScope(
            quality: NeonQuality.plain,
            child: LightWell(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(LightWell), findsOneWidget);

    final decorations = _paintedDecorations(tester);
    expect(
      decorations,
      isNotEmpty,
      reason: 'a positive control: without this the rest asserts nothing',
    );
    expect(
      decorations.any((d) => d.color == NeonTokens.groundColor),
      isTrue,
      reason: 'the plain tier must still paint the ground itself',
    );
    expect(
      decorations.every((d) => d.gradient == null),
      isTrue,
      reason: 'plain drops the falloff -- that is what makes it cheaper',
    );
  });

  testWidgets('a zero-sized well does not throw', (tester) async {
    // A LayoutBuilder inside a collapsed parent hands down a zero box,
    // and a radial gradient with radius 0 is a division waiting to
    // happen. Reachable during a route transition.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 0, height: 0, child: LightWell()),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  test('the tokens it depends on are sane', () {
    expect(NeonTokens.lightWellRadiusRatio, greaterThan(0));
    expect(NeonTokens.lightWellAlpha, greaterThan(0));
    expect(
      NeonTokens.lightWellAlpha,
      lessThan(0.2),
      reason: 'a well bright enough to notice is a gradient, not a ground',
    );
  });
}
