// Spec 1 W10a (batch 2 fix round 1): fixed-height sheets and the
// confirmation dialog grow with the phone's text size above 1.0, never
// shrink below today's height for small text, and stop at 90% of the screen.
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/core/widgets/feedback/confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = Size(390, 844);

Future<BuildContext> _pumpApp(WidgetTester t, double textScale) async {
  t.view.physicalSize = _phone;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
  late BuildContext context;
  // A fresh app each time: no sheet or dialog left open from a previous pump.
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(
    ScreenUtilConfig.builder(
      builder:
          (_) => MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
    ),
  );
  return context;
}

Future<double> _sheetMax(
  WidgetTester t,
  double textScale, {
  double? designMax,
}) async {
  final context = await _pumpApp(t, textScale);
  BottomSheetUtils.showDocumentationBottomSheet<void>(
    context: context,
    maxHeight: designMax?.h,
    widget: const SizedBox(height: 10),
  );
  await t.pumpAndSettle();
  return t.widget<BottomSheet>(find.byType(BottomSheet)).constraints!.maxHeight;
}

ConfirmationDialog _dialog() => ConfirmationDialog(
  type: ConfirmationType.warning,
  title: 'Sign out all other devices?',
  message: 'Every other phone signed in to your account will be signed out.',
  confirmText: 'Sign out others',
  onConfirm: () {},
);

Future<double> _dialogMax(WidgetTester t, double textScale) async {
  final context = await _pumpApp(t, textScale);
  showDialog<void>(context: context, builder: (_) => _dialog());
  await t.pumpAndSettle();
  return t
      .widget<ConstrainedBox>(
        find
            .descendant(
              of: find.byType(ConfirmationDialog),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      )
      .constraints
      .maxHeight;
}

void main() {
  testWidgets('a fixed sheet keeps its height at 1.0 and below', (t) async {
    expect(await _sheetMax(t, 1.0, designMax: 400), 400.h);
    expect(await _sheetMax(t, 0.85, designMax: 400), 400.h);
  });

  testWidgets('a fixed sheet grows with large text, up to 90% of the screen', (
    t,
  ) async {
    expect(await _sheetMax(t, 1.3, designMax: 400), closeTo(400.h * 1.3, 0.01));
    expect(await _sheetMax(t, 2.0, designMax: 400), _phone.height * 0.9);
  });

  testWidgets('a sheet taller than the screen allows is never cut down', (
    t,
  ) async {
    // Today's 95% sheets stay as they are at every size.
    expect(await _sheetMax(t, 2.0, designMax: 812 * 0.95), (812 * 0.95).h);
  });

  testWidgets('a sheet with no fixed height is 90% of the screen', (t) async {
    expect(await _sheetMax(t, 1.0), _phone.height * 0.9);
    expect(await _sheetMax(t, 2.0), _phone.height * 0.9);
  });

  testWidgets('the dialog never shrinks below 350 for small text', (t) async {
    expect(await _dialogMax(t, 1.0), 350.h);
    expect(await _dialogMax(t, 0.85), 350.h);
    expect(await _dialogMax(t, 2.0), closeTo(700.h, 0.01));
  });
}
