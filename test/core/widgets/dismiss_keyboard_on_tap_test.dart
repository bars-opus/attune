import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/core/widgets/dismiss_keyboard_on_tap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a tap on empty space hides the keyboard; taps on the field and buttons still reach them', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DismissKeyboardOnTap(
          child: Column(children: [
            const TextField(),
            TextButton(onPressed: () => pressed++, child: const Text('Go')),
            const SizedBox(height: 300, width: double.infinity, child: Text('blank')),
          ]),
        ),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byType(TextField)); // tapping the field again keeps it
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(pressed, 1, reason: 'buttons still work');

    await tester.tap(find.text('blank'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets("every BottomSheetUtils sheet hides the keyboard on a tap outside its field", (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(800, 600),
      builder: (_, __) => MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => BottomSheetUtils.showDocumentationBottomSheet<void>(
              context: context,
              widget: const Column(children: [TextField(), SizedBox(height: 200, child: Text('blank'))]),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('blank'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
