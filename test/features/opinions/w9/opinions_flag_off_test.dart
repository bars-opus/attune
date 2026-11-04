// Spec 1 W9 (owner ruling 2026-11-04): with opinions_safety_v1 off, the
// Opinions screens W9 edits look and behave exactly as before W9. The
// goldens below were written from the code BEFORE W9a's first edit (plan
// Task 1, Step 4); every later task runs this file unchanged, without
// --update-goldens. The only ungated change, OPN-DELETE-RLS, is in the
// repository, below the screens.
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/screen/edit_opinion_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/quote_compose_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_opinions.dart';

Future<void> _golden(String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/flag_off_$name.png'),
);

const _sixReasons = [
  'Identifies a real person',
  'Harmful or dangerous content',
  'Explicit sexual content',
  'Hate speech or discrimination',
  'Spam',
  'Other',
];

void main() {
  testWidgets('compose, edit and quote look as before', (tester) async {
    final repo = FakeOpinionRepository();
    await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'A draft that is long enough to post.',
    );
    await tester.pumpAndSettle();
    await _golden('compose');

    await pumpOpinionScreen(
      tester,
      () => EditOpinionScreen(opinion: w9Opinion(mine: true)),
      repo: repo,
    );
    await _golden('edit');

    await pumpOpinionScreen(
      tester,
      () => QuoteComposeScreen(quotedOpinion: w9Opinion()),
      repo: repo,
    );
    await _golden('quote');
  });

  testWidgets('a failed post still says so in a snackbar, draft kept', (
    tester,
  ) async {
    final repo = FakeOpinionRepository()..refuseWith = Exception('network');
    await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'A draft that is long enough to post.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to post:'), findsOneWidget);
    expect(find.text('A draft that is long enough to post.'), findsOneWidget);
  });

  testWidgets('the thread, its post menu and both report lists are as before', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    final opinion = w9Opinion();
    await pumpOpinionScreen(
      tester,
      () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
      repo: repo,
    );
    await _golden('thread');

    // The post menu (OpinionMoreData): no support row.
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await _golden('post_menu');
    expect(find.text('Need support now?'), findsNothing);
    // Under the test font, copy and icon glyphs render as boxes, so the
    // golden cannot see them: pin them here (review M-9).
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await _golden('report_reasons');
    for (final r in _sixReasons) {
      expect(find.text(r), findsOneWidget, reason: r);
    }
    expect(find.text('Someone may be at risk'), findsNothing);
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    expect(repo.reports, ['opinion:o1:Spam']);
    expect(
      find.text('Thank you. We will review this within 24 hours.'),
      findsOneWidget,
    );
  });

  testWidgets('comment menus and the comment report list are as before', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    final opinion = w9Opinion();
    await pumpOpinionScreen(
      tester,
      () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
      repo: repo,
    );
    Iterable<String?> items() => find
        .byType(PopupMenuItem<String>)
        .evaluate()
        .map((e) => ((e.widget as PopupMenuItem<String>).child as Text).data);
    // Top-level comments show newest first: mine (index 0), then the other.
    final menus = find.byIcon(Icons.more_horiz);
    expect(menus, findsNWidgets(2));
    await tester.tap(menus.at(0));
    await tester.pumpAndSettle();
    expect(items(), ['Edit', 'Delete']);
    await tester.tapAt(const Offset(5, 5)); // close the menu
    await tester.pumpAndSettle();
    await tester.tap(menus.at(1));
    await tester.pumpAndSettle();
    expect(items(), ['Report']);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ListTile),
          )
          .evaluate()
          .map((e) => ((e.widget as ListTile).title as Text).data),
      _sixReasons,
    );
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    // Today a comment report never reaches the server (plan P-14).
    expect(repo.reports, isEmpty);
  });
}
