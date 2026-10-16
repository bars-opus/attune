// test/features/couple_map/distance_card_test.dart
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/presentation/providers/couple_map_providers.dart';
import 'package:attune/features/couple_map/presentation/widgets/distance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const _people = CoupleMapPeople(
  selfInitials: 'AM',
  partnerInitials: 'K',
  partnerName: 'Kofi',
);

Future<void> _pump(WidgetTester t, Widget w, {double width = 390}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder:
          (_, __) => MaterialApp(
            home: Scaffold(
              body: Align(alignment: Alignment.bottomCenter, child: w),
            ),
          ),
    ),
  );
}

void main() {
  testWidgets('headline and " · " details; one readable label', (t) async {
    final semantics = t.ensureSemantics();
    await _pump(
      t,
      const DistanceCard(
        copy: DistanceCardCopy(
          headline: '8 hours by road',
          details: '412 km apart · in Accra',
          together: false,
        ),
        people: _people,
      ),
    );
    expect(find.text('8 hours by road'), findsOneWidget);
    expect(find.text('412 km apart · in Accra'), findsOneWidget);
    expect(
      find.bySemanticsLabel('8 hours by road. 412 km apart · in Accra'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('together: a warm accent, no details line', (t) async {
    await _pump(
      t,
      const DistanceCard(
        copy: DistanceCardCopy(
          headline: 'Together · Accra',
          details: '',
          together: true,
        ),
        people: _people,
      ),
    );
    final headline = t.widget<Text>(find.text('Together · Accra'));
    final primary =
        Theme.of(t.element(find.text('Together · Accra'))).colorScheme.primary;
    expect(headline.style?.color, primary);
  });

  testWidgets('long copy never overflows at 320 dp', (t) async {
    await _pump(
      t,
      const DistanceCard(
        copy: DistanceCardCopy(
          headline: "12 days until you're together",
          details: '5.1k km apart · in Llanfairpwllgwyngyll · 11:15pm there',
          together: false,
        ),
        people: _people,
      ),
      width: 320,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'notice: the neutral line is not a button; the onboarding line is',
    (t) async {
      await _pump(t, const NoticeCard(notice: CoupleMapNotice.justYou));
      expect(find.text('Just you on the map right now'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
      var taps = 0;
      await _pump(
        t,
        NoticeCard(notice: CoupleMapNotice.notSharing, onTap: () => taps++),
      );
      await t.tap(find.byType(NoticeCard));
      expect(taps, 1);
    },
  );
  testWidgets('a broken avatar URL shows initials quietly (no error report)', (
    t,
  ) async {
    await _pump(
      t,
      const DistanceCard(
        copy: DistanceCardCopy(
          headline: '8 hours by road',
          details: '',
          together: false,
        ),
        people: CoupleMapPeople(
          selfUrl: 'https://invalid.example/a.jpg',
          selfInitials: 'AM',
          partnerInitials: 'K',
          partnerName: 'Kofi',
        ),
      ),
    );
    final avatars = t.widgetList<CircleAvatar>(find.byType(CircleAvatar));
    expect(
      avatars.any(
        (a) => a.foregroundImage != null && a.onForegroundImageError != null,
      ),
      isTrue,
    );
  });
}
