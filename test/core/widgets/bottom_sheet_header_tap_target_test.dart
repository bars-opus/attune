// Spec 5 (R5-13, plan review I5): the sheet header's action is a 44 x 44 dp
// target (WCAG 2.5.8 / platform guidance) without making the header taller.
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a 44 dp action, same header height', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => const MaterialApp(
        home: Scaffold(body: Column(children: [BottomSheetHeader(title: 'Plan')])),
      ),
    ));
    final button = t.getSize(find.byType(TextButton));
    final header = t.getSize(find.byType(BottomSheetHeader));
    expect(button.height, greaterThanOrEqualTo(44));
    expect(button.width, greaterThanOrEqualTo(44));
    expect(header.height, lessThanOrEqualTo(kHeaderHeight));
  });

  testWidgets('a wider phone: no taller than before (final review M-7)', (t) async {
    t.view.physicalSize = const Size(1290, 2796); // 430 x 932
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => const MaterialApp(
        home: Scaffold(body: Column(children: [BottomSheetHeader(title: 'Plan')])),
      ),
    ));
    final before = 2 * 16 * 430 / 390 + 24; // the old Padding(all: md.w) + label
    expect(t.getSize(find.byType(BottomSheetHeader)).height, closeTo(before, 0.5));
  });
}

// Measured at 390 dp. On any width the header stays 2 x 16.w + 24: the label
// and the 44 dp target do not scale, so the fixed 10 dp give-back is exact
// (final review M-7).
// Measured before the change (Spec 5): the header's height must not grow.
const double kHeaderHeight = 56;
