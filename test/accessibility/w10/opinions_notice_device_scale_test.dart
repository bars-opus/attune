// Spec 1 W10a (batch 4 fix round 2, N-1 and N-2): the comment composer's
// refusal notice reads the phone's own text size (AllowLargeText) even while
// the root clamp holds the thread at 1.0, which is what ships until
// text_scale_v2 is on. At a large phone size it is still held to a quarter
// of the screen, it shows that it scrolls, and the composer fits on screen.
//   flutter test test/accessibility/w10/opinions_notice_device_scale_test.dart
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/content_filter_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/opinions/w9/support/fake_opinions.dart';
import '../../helpers/flow_harness.dart';

const _phone = Size(360, 780);

Future<void> _refuseAComment(WidgetTester t, double scale) async {
  final repo = FakeOpinionRepository();
  final opinion = w9Opinion();
  await pumpFlowScreen(
    t,
    () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
    textScale: scale,
    size: _phone,
    overrides: opinionOverrides(repo),
  );
  repo.refuseWith = const PostgrestException(
    message: 'content:contact_info',
    code: '22023',
  );
  await t.enterText(find.byType(TextField).last, 'my ig: kofi.99');
  await t.pump();
  await t.tap(find.byIcon(Icons.send_rounded));
  await t.pumpAndSettle();
  expect(find.byType(ContentFilterNotice), findsOneWidget);
}

Finder _noticeAncestor(Type type) => find.ancestor(
  of: find.byType(ContentFilterNotice),
  matching: find.byType(type),
);

void main() {
  for (final scale in const [1.3, 1.6, 2.0]) {
    testWidgets('root clamp 1.0, phone text $scale: the notice is held to a '
        'quarter of the screen, shows it scrolls, and the composer fits', (
      t,
    ) async {
      await _refuseAComment(t, scale);
      // Held to a quarter of the screen, in a view that scrolls.
      final view = _noticeAncestor(SingleChildScrollView);
      expect(view, findsOneWidget);
      expect(t.getSize(view).height, lessThanOrEqualTo(_phone.height * 0.25));
      // Its scrollbar is always shown (N-2).
      final bar = t.widget<Scrollbar>(_noticeAncestor(Scrollbar));
      expect(bar.thumbVisibility, isTrue);
      // The composer (the notice and the field) fits on screen.
      final composer = t.getRect(_noticeAncestor(SafeArea).first);
      expect(composer.top, greaterThanOrEqualTo(0));
      expect(composer.bottom, lessThanOrEqualTo(_phone.height));
    });
  }

  testWidgets('at the normal size the notice is as before: no scroll view, '
      'no scrollbar', (t) async {
    await _refuseAComment(t, 1.0);
    expect(_noticeAncestor(SingleChildScrollView), findsNothing);
    expect(_noticeAncestor(Scrollbar), findsNothing);
  });
}
