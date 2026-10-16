import 'package:attune/core/widgets/app_tabs.dart';
import 'package:attune/home/widgets/tabs_with_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(int count) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder:
      (_, __) => MaterialApp(
        home: Scaffold(
          body: TabsWithContent(
            tabs: [
              for (var i = 0; i < count; i++)
                AppTabItem(label: 'Tab $i', content: Text('Page $i')),
            ],
            initialIndex: 0,
            showContent: true,
          ),
        ),
      ),
);

void main() {
  // A tab that appears once a feature flag loads (Planning's Map tab)
  // changes the count after the first frame; the controller is rebuilt.
  testWidgets('the tab count can change after the first frame', (t) async {
    await t.pumpWidget(_app(2));
    await t.pumpWidget(_app(3));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Tab 2'), findsOneWidget);
    await t.pumpWidget(_app(2));
    await t.pumpAndSettle();
    expect(find.text('Tab 2'), findsNothing);
  });
}
