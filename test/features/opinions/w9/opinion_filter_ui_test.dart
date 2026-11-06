// Spec 1 W9a (§8 W9a, §2.3): a post, quote, edit, comment or comment edit
// the content filter refuses shows the reason inline, under the field; the
// draft stays; it is announced and counted (opinion_blocked:<reason>);
// typing again clears it; any other failure keeps today's message.
//   flutter test --update-goldens test/features/opinions/w9/opinion_filter_ui_test.dart
import 'package:attune/features/opinions/domain/content_filter_error.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/screen/edit_opinion_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/core/widgets/poll_composer.dart';
import 'package:attune/features/opinions/presentation/screen/quote_compose_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/content_filter_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/flow_harness.dart';
import 'support/fake_opinions.dart';
import '../../../helpers/tap_in_reach.dart';

PostgrestException _refusal(String wire, {String? hint}) =>
    PostgrestException(message: 'content:$wire', code: '22023', hint: hint);

const _contact =
    "Phone numbers, emails, links and usernames can't go in Opinions. They can identify you or someone else. Take it out and post again.";
const _slur =
    'This includes a word that attacks people for who they are. Opinions doesn\'t allow it.';
const _explicit =
    "Opinions doesn't allow sexual content. You can describe what happened without explicit words.";
const _quoted =
    "The comment you're replying to can't be quoted in Opinions. Your own words are fine. Close the reply and post again.";
const _pollOption = "It's in one of your poll options.";

void main() {
  test('the three refusals, and nothing else, are read as filter errors', () {
    expect(
      ContentFilterReason.of(_refusal('contact_info')),
      ContentFilterReason.contactInfo,
    );
    expect(ContentFilterReason.of(_refusal('slur')), ContentFilterReason.slur);
    expect(
      ContentFilterReason.of(_refusal('explicit')),
      ContentFilterReason.explicit,
    );
    expect(ContentFilterReason.of(_refusal('other')), isNull);
    expect(
      ContentFilterReason.of(const PostgrestException(message: 'cooldown')),
      isNull,
    );
    expect(ContentFilterReason.of(Exception('content:slur')), isNull);
    expect(ContentFilterReason.values.map((r) => r.metric.key), [
      'opinion_blocked:contact_info',
      'opinion_blocked:slur',
      'opinion_blocked:explicit',
    ]);
    // Which part was refused: the RPC's HINT (batch-3 review I-3).
    expect(ContentFilterPart.of(_refusal('slur')), ContentFilterPart.text);
    expect(
      ContentFilterPart.of(_refusal('slur', hint: 'quoted_text')),
      ContentFilterPart.quotedText,
    );
    expect(
      ContentFilterPart.of(_refusal('slur', hint: 'poll_option')),
      ContentFilterPart.pollOption,
    );
    expect(
      ContentFilterPart.of(_refusal('slur', hint: 'other')),
      ContentFilterPart.text,
    );
    expect(ContentFilterPart.of(Exception('x')), ContentFilterPart.text);
  });

  testWidgets('compose: the reason shows under the field and the draft stays', (
    tester,
  ) async {
    final repo = FakeOpinionRepository()..refuseWith = _refusal('contact_info');
    final h = await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'Call me on 0244123456 tonight please',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.text(_contact), findsOneWidget);
    expect(find.text('Call me on 0244123456 tonight please'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(h.metrics, ['opinion_blocked:contact_info']);
    // Typing again clears it.
    await tester.enterText(
      find.byType(TextFormField),
      'Call me tonight please, I will be up',
    );
    await tester.pumpAndSettle();
    expect(find.text(_contact), findsNothing);
  });

  testWidgets('quote and edit: the same, by reason', (tester) async {
    final repo = FakeOpinionRepository()..refuseWith = _refusal('slur');
    final hq = await pumpOpinionScreen(
      tester,
      () => QuoteComposeScreen(quotedOpinion: w9Opinion()),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'A take with a word in it here',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.text(_slur), findsOneWidget);
    expect(find.text('A take with a word in it here'), findsOneWidget);
    expect(hq.metrics, ['opinion_blocked:slur']);
    await tester.enterText(find.byType(TextFormField), 'A take, changed');
    await tester.pumpAndSettle();
    expect(find.text(_slur), findsNothing);

    repo.refuseWith = _refusal('explicit');
    final h = await pumpOpinionScreen(
      tester,
      () => EditOpinionScreen(opinion: w9Opinion(mine: true)),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'An edit with explicit words',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text(_explicit), findsOneWidget);
    expect(find.text('An edit with explicit words'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(h.metrics, ['opinion_blocked:explicit']);
    await tester.enterText(find.byType(TextFormField), 'An edit, changed');
    await tester.pumpAndSettle();
    expect(find.text(_explicit), findsNothing);
  });

  testWidgets(
    'a comment, and a comment edit: the reason shows, the words stay',
    (tester) async {
      final repo = FakeOpinionRepository();
      final opinion = w9Opinion();
      final h = await pumpOpinionScreen(
        tester,
        () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
        repo: repo,
      );
      repo.refuseWith = _refusal('contact_info');
      await tester.enterText(find.byType(TextField).last, 'my ig: kofi.99');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.text(_contact), findsOneWidget);
      expect(find.text('my ig: kofi.99'), findsOneWidget);
      expect(h.metrics, ['opinion_blocked:contact_info']);
      // A cursor move keeps it; typing clears it (batch-3 review I-2).
      final comment = tester.widget<TextField>(find.byType(TextField).last);
      comment.controller!.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      expect(find.text(_contact), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'my ig is private');
      await tester.pump();
      expect(find.text(_contact), findsNothing);
      // Refused again, then sent: the notice goes with the sent words.
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.text(_contact), findsOneWidget);
      expect(h.metrics, [
        'opinion_blocked:contact_info',
        'opinion_blocked:contact_info',
      ]);

      // Inline edit of my own comment (the first menu: newest first).
      repo.refuseWith = _refusal('slur');
      await tapInReach(tester, find.byIcon(Icons.more_horiz).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'My own comment here.'),
        'My own comment, changed.',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text(_slur), findsOneWidget);
      expect(find.text('My own comment, changed.'), findsOneWidget);
      expect(h.metrics, [
        'opinion_blocked:contact_info',
        'opinion_blocked:contact_info',
        'opinion_blocked:slur',
      ]);
      // Typing in the editor clears it (I-2).
      await tester.enterText(
        find.widgetWithText(TextField, 'My own comment, changed.'),
        'My own comment, changed again.',
      );
      await tester.pump();
      expect(find.text(_slur), findsNothing);
      // Cancel clears it.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text(_slur), findsOneWidget);
      await tapInReach(tester, find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text(_slur), findsNothing);
      // The refused comment, sent at last: its notice goes with it.
      expect(find.text(_contact), findsOneWidget);
      repo.refuseWith = null;
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.text(_contact), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets('starting another edit clears the last one\'s refusal', (
    tester,
  ) async {
    final repo =
        FakeOpinionRepository()
          ..comments = [
            w9Comment('c-mine', mine: true),
            w9Comment('c-mine2', mine: true, content: 'My second comment.'),
          ];
    final opinion = w9Opinion();
    await pumpOpinionScreen(
      tester,
      () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
      repo: repo,
    );
    // Opens the first comment menu that offers Edit.
    Future<void> editNext() async {
      final menus = find.byIcon(Icons.more_horiz);
      for (var i = 0; i < menus.evaluate().length; i++) {
        await tester.tap(menus.at(i), warnIfMissed: false);
        await tester.pumpAndSettle();
        if (find.text('Edit').evaluate().isNotEmpty) {
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
          return;
        }
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
      fail('no Edit menu');
    }

    repo.refuseWith = _refusal('slur');
    await editNext();
    // The inline editor sits in the list, above the comment field.
    final editor = find.byType(TextField).first;
    await tester.enterText(editor, 'Changed words here.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text(_slur), findsOneWidget);
    await editNext();
    expect(find.text(_slur), findsNothing);
  });

  testWidgets('a refused quote of the comment replied to is not blamed on '
      'the writer', (tester) async {
    final repo = FakeOpinionRepository();
    final opinion = w9Opinion();
    final h = await pumpOpinionScreen(
      tester,
      () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
      repo: repo,
    );
    repo.refuseWith = _refusal('slur', hint: 'quoted_text');
    await tester.enterText(find.byType(TextField).last, 'I agree with this');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text(_quoted), findsOneWidget);
    expect(find.text(_slur), findsNothing);
    expect(find.text('I agree with this'), findsOneWidget);
    expect(h.metrics, ['opinion_blocked:slur']);
  });

  testWidgets('a refused poll option says where, and changing the poll '
      'clears it', (tester) async {
    final repo =
        FakeOpinionRepository()
          ..refuseWith = _refusal('contact_info', hint: 'poll_option');
    final h = await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'Which one should I pick, friends?',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.text(_contact), findsOneWidget);
    expect(find.text(_pollOption), findsOneWidget);
    expect(find.text('Which one should I pick, friends?'), findsOneWidget);
    expect(h.metrics, ['opinion_blocked:contact_info']);
    tester.widget<PollComposerRow>(find.byType(PollComposerRow)).onChanged([
      'This one',
      'That one',
    ]);
    await tester.pumpAndSettle();
    expect(find.text(_pollOption), findsNothing);
    expect(find.text(_contact), findsNothing);
  });

  testWidgets('any other failure keeps today\'s message', (tester) async {
    final repo =
        FakeOpinionRepository()
          ..refuseWith = const PostgrestException(
            message: 'cooldown',
            code: '53400',
          );
    final h = await pumpOpinionScreen(
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
    expect(find.byType(ContentFilterNotice), findsNothing);
    expect(h.metrics, isEmpty);
  });

  testWidgets('the notice: guidelines and goldens', (tester) async {
    Widget notice() => const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(16),
        child: ContentFilterNotice(reason: ContentFilterReason.contactInfo),
      ),
    );
    await pumpFlowScreen(tester, notice);
    await expectFlowGuidelines(tester);
    // One node whose words are the whole message (the icon says nothing of
    // its own) (batch-3 review M-5). Not a live region: the explicit
    // announce speaks it once (W9 final M-6).
    expect(
      tester.getSemantics(find.byType(ContentFilterNotice)),
      matchesSemantics(isLiveRegion: false, label: _contact),
    );
    await expectFlowGoldens(tester, 'content_filter_notice', notice);
  });
}
