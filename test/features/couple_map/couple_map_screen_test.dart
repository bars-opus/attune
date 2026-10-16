// The full-screen map (owner, 2026-10-16): no app bar or tabs; a Back
// button left of the sharing chip; every control clears the notch and the
// home bar.
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/presentation/screens/couple_map_screen.dart';
import 'package:attune/features/couple_map/presentation/widgets/sharing_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tab_harness.dart';

void main() {
  testWidgets(
    'a Back button sits left of the sharing chip and closes the map',
    (t) async {
      var backs = 0;
      final h = TabHarness([selfRow])..onBack = () => backs++;
      await h.pump(t);
      final back = find.byTooltip('Back');
      expect(back, findsOneWidget);
      expect(
        t.getCenter(back).dx,
        lessThan(t.getCenter(find.byType(SharingChip)).dx),
      );
      expect(t.getSize(back).width, greaterThanOrEqualTo(48));
      expect(t.getSize(back).height, greaterThanOrEqualTo(48));
      await t.tap(back);
      await t.pumpAndSettle();
      expect(backs, 1);
    },
  );

  testWidgets('without a Back action there is no Back button', (t) async {
    final h = TabHarness([selfRow]);
    await h.pump(t);
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('the list fallback (no map) keeps the Back button', (t) async {
    var backs = 0;
    final h =
        TabHarness([selfRow])
          ..token = ''
          ..onBack = () => backs++;
    await h.pump(t);
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('controls clear the notch and the home bar', (t) async {
    final h =
        TabHarness([selfRow, partnerRow()])
          ..onBack = () {}
          ..padding = const EdgeInsets.only(top: 47, bottom: 34);
    await h.pump(t);
    for (final f in [
      find.byTooltip('Back'),
      find.byType(SharingChip),
      find.byTooltip('Satellite view'),
    ]) {
      expect(t.getTopLeft(f).dy, greaterThanOrEqualTo(47 + 16), reason: '$f');
    }
    // The compass sits below the right-hand column, which moved down too.
    expect(
      h.view.builtOrnamentTop,
      CoupleMapConfig.rightColumnBottom(stories: false) + 47,
    );
  });

  testWidgets('CoupleMapScreen is full screen and Back pops it', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          coupleMapBodyBuilderProvider.overrideWithValue(
            (rel, onBack) =>
                TextButton(onPressed: onBack, child: Text('map for $rel')),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => openCoupleMap(context, 'r1'),
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('map for r1'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    await t.tap(find.text('map for r1'));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('map for r1'), findsNothing);
  });
}
