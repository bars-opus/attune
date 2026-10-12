import 'package:attune/core/ui/neon/light_well.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
