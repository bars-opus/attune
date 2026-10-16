// The map's sheets sit on the app's neutral page colour, never the M3
// primary-tinted surface (owner, 2026-10-16).
import 'package:attune/features/couple_map/presentation/widgets/sharing_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tab_harness.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final (name, open) in <(String, Future<void> Function(WidgetTester))>[
      ('sharing', (t) => t.tap(find.byType(SharingChip))),
      ('list', (t) => t.tap(find.byTooltip('List'))),
    ]) {
      testWidgets('the $name sheet is neutral ($mode)', (t) async {
        final h = TabHarness([selfRow, partnerRow()])..themeMode = mode;
        await h.pump(t);
        await open(t);
        await t.pumpAndSettle();
        final sheet = t.widget<BottomSheet>(find.byType(BottomSheet));
        final page =
            Theme.of(
              t.element(find.byType(BottomSheet)),
            ).scaffoldBackgroundColor;
        expect(sheet.backgroundColor, page);
        // What actually paints: the sheet's Material, untinted.
        final material = t.widget<Material>(
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, page);
        expect(
          material.surfaceTintColor ?? Colors.transparent,
          Colors.transparent,
        );
      });
    }
  }
}
