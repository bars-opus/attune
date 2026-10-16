// test/features/couple_map/sharing_chip_test.dart
import 'package:attune/features/couple_map/presentation/widgets/sharing_chip.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget w) => t.pumpWidget(
  ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, __) => MaterialApp(home: Scaffold(body: Center(child: w))),
  ),
);

void main() {
  testWidgets(
    'shows the label, is a 44 dp target, says what it does, and taps',
    (t) async {
      final semantics = t.ensureSemantics();
      var taps = 0;
      await _pump(
        t,
        SharingChip(
          label: 'Sharing my area with Kofi',
          status: PresenceStatus.sharing,
          locationOff: false,
          onTap: () => taps++,
        ),
      );
      expect(find.text('Sharing my area with Kofi'), findsOneWidget);
      expect(
        t.getSize(find.byType(SharingChip)).height,
        greaterThanOrEqualTo(44),
      );
      final chip = find.bySemanticsLabel(
        RegExp('Sharing: Sharing my area with Kofi'),
      );
      expect(chip, findsOneWidget);
      // Activatable by a screen reader, not just announced (checklist 5.6).
      expect(t.getSemantics(chip), containsSemantics(hasTapAction: true));
      await t.tap(find.byType(SharingChip));
      expect(taps, 1);
      semantics.dispose();
    },
  );

  testWidgets('a long label ellipsizes instead of overflowing at 320 dp', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(
      t,
      SharingChip(
        label: 'Sharing my area with Kwabena Ofori-Atta Mensah',
        status: PresenceStatus.sharing,
        locationOff: false,
        onTap: () {},
      ),
    );
    expect(t.takeException(), isNull);
  });
}
