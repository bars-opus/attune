// Spec 1 W10a: Opinions at large text (audit order: 2nd). A thread with
// two comments, then its post menu and the post report list, with
// opinions_safety_v1 off (W9's flag-off goldens stay as they are).
//   flutter test --update-goldens test/accessibility/w10/opinions_large_text_test.dart
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/opinions/w9/support/fake_opinions.dart';
import '../../helpers/flow_harness.dart';
import 'support/large_text_audit.dart';

void main() {
  for (final phone in auditPhones) {
    for (final scale in auditScales) {
      testWidgets('Opinions, ${phone.width.toInt()} wide, text $scale', (
        t,
      ) async {
        final golden =
            phone == auditPhones.first && goldenScales.contains(scale);
        final opinion = w9Opinion();
        final overflows = await collectOverflows(() async {
          await pumpFlowScreen(
            t,
            () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
            textScale: scale,
            rootTextScaleCap: scale,
            size: phone,
            overrides: opinionOverrides(FakeOpinionRepository()),
          );
          if (golden) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                'goldens/opinions_thread.${scaleName(scale)}.png',
              ),
            );
          }
          _expectTimesAtMostTwoLines(t);
          await scrollToEnd(t);
          _expectLastCommentAboveComposer(t);
          await t.tap(find.byIcon(Icons.more_vert_rounded));
          await t.pumpAndSettle();
          if (golden) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                'goldens/opinions_post_menu.${scaleName(scale)}.png',
              ),
            );
          }
          await t.tapAt(const Offset(20, 20));
          await t.pumpAndSettle();
        });
        expect(overflows, isEmpty);
      });
    }
  }
}

/// Batch 3 fix round 1 (I-1): each time ("1m ago") stays on at most two
/// lines; it never becomes a column of single glyphs beside the menu.
void _expectTimesAtMostTwoLines(WidgetTester t) {
  final times = find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').contains(' ago'),
  );
  expect(times, findsWidgets);
  for (final element in times.evaluate()) {
    final text = element.widget as Text;
    final oneLine = TextPainter(
      text: TextSpan(
        text: 'x',
        style: DefaultTextStyle.of(element).style.merge(text.style),
      ),
      textScaler: MediaQuery.textScalerOf(element),
      textDirection: TextDirection.ltr,
    )..layout();
    final height = (element.renderObject! as RenderBox).size.height;
    expect(
      height,
      lessThanOrEqualTo(2 * oneLine.height + 0.5),
      reason: '"${text.data}" is ${height / oneLine.height} lines',
    );
  }
}

/// Batch 3 fix round 1 (M-5): scrolled to the end, the last comment's row
/// (its menu) sits above the floating composer, not behind it.
void _expectLastCommentAboveComposer(WidgetTester t) {
  final menus = find.byIcon(Icons.more_horiz);
  expect(menus, findsWidgets);
  final lastMenu = t.getRect(menus.last);
  final composer = t.getRect(find.byType(ChatTextField));
  expect(lastMenu.bottom, lessThanOrEqualTo(composer.top));
}
