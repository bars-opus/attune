// test/features/couple_map/couple_map_list_test.dart
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/presentation/widgets/couple_map_list_sheet.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, CoupleMapPresence p, CoupleMapNotice? n) =>
    t.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: CoupleMapListContent(
                  presence: p,
                  partnerName: 'Kofi',
                  notice: n,
                  now: DateTime.utc(2026, 9, 2, 14, 15),
                ),
              ),
            ),
      ),
    );

void main() {
  testWidgets(
    'presence rows: "{Partner}" with "city · time there" (spec §3.5)',
    (t) async {
      final p = CoupleMapPresence.fromRows([
        {
          'who': 'self',
          'cell_lat': 5.565,
          'cell_lng': -0.208,
          'city': 'Accra',
          'freshness': 'fresh',
        },
        {
          'who': 'partner',
          'cell_lat': 51.505,
          'cell_lng': -0.121,
          'city': 'London',
          'utc_offset_minutes': 60,
          'freshness': 'fresh',
          'distance_km': 5100,
          'together': false,
        },
      ]);
      await _pump(t, p, null);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Accra'), findsOneWidget);
      expect(find.text('Kofi'), findsOneWidget);
      expect(find.text('London · 3:15pm there'), findsOneWidget);
    },
  );

  testWidgets(
    'no partner: the same neutral line as the map, nothing else about them',
    (t) async {
      final p = CoupleMapPresence.fromRows([
        {
          'who': 'self',
          'cell_lat': 5.565,
          'cell_lng': -0.208,
          'freshness': 'fresh',
        },
      ]);
      await _pump(t, p, CoupleMapNotice.justYou);
      expect(find.text('Just you on the map right now'), findsOneWidget);
      expect(find.text('Kofi'), findsNothing);
    },
  );

  testWidgets('never a time of update, an online state, or "last seen"', (
    t,
  ) async {
    final p = CoupleMapPresence.fromRows([
      {
        'who': 'self',
        'cell_lat': 5.565,
        'cell_lng': -0.208,
        'freshness': 'fresh',
      },
      {
        'who': 'partner',
        'cell_lat': 5.6,
        'cell_lng': -0.2,
        'freshness': 'fading',
        'distance_km': 5,
        'together': false,
      },
    ]);
    await _pump(t, p, null);
    for (final banned in ['ago', 'online', 'last seen', 'updated']) {
      expect(
        find.textContaining(RegExp(banned, caseSensitive: false)),
        findsNothing,
        reason: banned,
      );
    }
  });
}
