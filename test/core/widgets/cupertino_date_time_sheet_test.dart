import 'package:attune/core/widgets/cupertino_date_time_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(void Function(BuildContext) open) => ScreenUtilInit(
      designSize: const Size(800, 600), // 1:1 with the test view, so .h is a no-op
      builder: (_, __) => MaterialApp(
        home: Builder(builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open'))),
      ),
    );

void main() {
  testWidgets('with a sheetHeight it opens in the app sheet at that height, and reports changes', (tester) async {
    final seen = <DateTime>[];
    await tester.pumpWidget(_app((context) => showCupertinoDateTimeSheet(
          context: context,
          mode: CupertinoDatePickerMode.date,
          initialDateTime: DateTime(2026, 10, 12),
          onChanged: seen.add,
          sheetHeight: 350,
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget, reason: 'BottomSheetUtils');
    expect(tester.getSize(find.byType(DraggableScrollableSheet)).height, moreOrLessEquals(350, epsilon: 0.5));
    tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker)).onDateTimeChanged(DateTime(2026, 11, 20));
    expect(seen, [DateTime(2026, 11, 20)]);
  });

  testWidgets('without a sheetHeight it is the plain 216-high sheet, as before', (tester) async {
    await tester.pumpWidget(_app((context) => showCupertinoDateTimeSheet(
          context: context,
          mode: CupertinoDatePickerMode.date,
          initialDateTime: DateTime(2026, 10, 12),
          onChanged: (_) {},
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(tester.getSize(find.byType(CupertinoDatePicker)).height, 216);
  });
}
