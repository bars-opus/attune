import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(home: home),
    );

void main() {
  testWidgets('Done runs the given action instead of closing', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(Scaffold(body: BottomSheetHeader(title: 'Row 1', onPressed: () => done++))));
    await tester.tap(find.text('Done'));
    expect(done, 1);
  });

  testWidgets('without an action, Done still closes the sheet', (tester) async {
    await tester.pumpWidget(_app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const BottomSheetHeader(title: 'Poll')),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Poll'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Poll'), findsNothing);
  });
}
