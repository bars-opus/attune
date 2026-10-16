// test/home/tabs_with_content_controller_test.dart
import 'package:attune/core/widgets/app_tabs.dart';
import 'package:attune/home/widgets/tabs_with_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(int count, void Function(TabController) onController) =>
    ScreenUtilInit(
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
                onControllerCreated: onController,
              ),
            ),
          ),
    );

void main() {
  testWidgets('a rebuilt controller (tab count changed) is handed over too', (
    t,
  ) async {
    final got = <TabController>[];
    await t.pumpWidget(_app(2, got.add));
    await t.pump();
    await t.pumpWidget(_app(3, got.add));
    await t.pump();
    expect(got, hasLength(2));
    expect(got.last.length, 3);
    // The new one works: moving it shows the third page.
    got.last.index = 2;
    await t.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);
  });
}
