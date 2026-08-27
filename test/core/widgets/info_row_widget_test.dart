import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'tappable rows provide a Material surface when rendered in a bare overlay',
    (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (context, child) => MaterialApp(
                home: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder:
                          (context) => Center(
                            child: SizedBox(
                              width: 320,
                              child: InfoRowWidget(
                                title: 'Pinned message',
                                subtitle: 'Jump to this message',
                                icon: Icons.push_pin,
                                onTap: () => tapped = true,
                              ),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
        ),
      );

      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Pinned message'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(tapped, isTrue);
    },
  );

  testWidgets(
    'the trailing chevron centers vertically against a tall title+subtitle '
    'block, not against the row\'s top edge',
    (tester) async {
      // pinAvatar defaults to true, which sets the row's own
      // crossAxisAlignment to .start — before the IntrinsicHeight/Center
      // fix, that top-aligned every child including the trailing icon, so
      // it sat high whenever the title+subtitle content was tall enough to
      // make the row taller than the icon itself (a long subtitle, as
      // here).
      // Column, not Center: a Center inside an unbounded viewport gives
      // its child loose (0..infinity) height constraints, which papers
      // over the exact bug this test targets (an unconstrained Row
      // without IntrinsicHeight still shrink-wraps to its own content and
      // reports a deceptively "correct" outer rect). A Column of real
      // finite width matches how InfoRowWidget is actually used — stacked
      // rows in a Settings-style list — and is the context the original
      // top-alignment bug was reported in.
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (context, child) => MaterialApp(
                home: Scaffold(
                  body: Column(
                    children: [
                      SizedBox(
                        width: 320,
                        child: InfoRowWidget(
                          title: 'Pinned message',
                          subtitle:
                              'A much longer subtitle that wraps across '
                              'several lines so the title+subtitle column '
                              'is the tallest thing in the row, taller '
                              'than the trailing chevron on its own.',
                          icon: Icons.push_pin,
                          showTrailingArrow: true,
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      );

      expect(tester.takeException(), isNull);

      final rowRect = tester.getRect(find.byType(InfoRowWidget));
      final chevronRect = tester.getRect(find.byIcon(Icons.chevron_right));

      // The chevron's own vertical center must land at the row's vertical
      // center — a couple of pixels of tolerance for icon glyph padding,
      // not for a systematic top-alignment bug (which would be off by
      // roughly half the title+subtitle block's extra height, far more
      // than this tolerance allows).
      expect(
        chevronRect.center.dy,
        closeTo(rowRect.center.dy, 3),
      );
    },
  );
}
