// Spec 1 W9b (§8 W9b, §2.2, §2.3, §6.6): with opinions_safety_v1 on,
// "Need support now?" is in compose and in every post and comment menu and
// opens Support (counted); both report lists start with "Someone may be at
// risk", which reaches the server with that reason and thanks the reporter
// without animation, offering the emergency numbers; a failed at-risk report
// says so. The manual's passage shows only with the flag.
// Batch 6 carries: every comment report reason reaches the server (owner
// ruling (c)); the other reasons' thanks promises only that it was sent;
// the report lists let large text through; the failure is announced and
// at least 4.5:1 in both themes.
//   flutter test --update-goldens test/features/opinions/w9/opinions_safety_ui_test.dart
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/feature_flag_refresher.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/opinions/presentation/providers/opinions_safety_provider.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/quote_compose_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:attune/features/opinions/presentation/widgets/need_support_link.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import 'support/fake_opinions.dart';
import '../../../helpers/tap_in_reach.dart';

final _on = [opinionsSafetyProvider.overrideWithValue(true)];

const _thanks =
    'Thank you. A person on our team will look at this soon. If someone is in danger right now, call your local emergency number.';
const _sent = 'Thank you. Your report has been sent.';
const _failed = "Couldn't send your report. Please try again.";
const _old24h = 'Thank you. We will review this within 24 hours.';
const _sixReasons = [
  'Identifies a real person',
  'Harmful or dangerous content',
  'Explicit sexual content',
  'Hate speech or discrimination',
  'Spam',
  'Other',
];

Future<FlowHarness> _thread(
  WidgetTester tester,
  FakeOpinionRepository repo, {
  double textScale = 1.0,
}) {
  final opinion = w9Opinion();
  return pumpOpinionScreen(
    tester,
    () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
    repo: repo,
    overrides: _on,
    textScale: textScale,
  );
}

Future<void> _openCommentReport(WidgetTester tester) async {
  await tapInReach(tester, find.byIcon(Icons.more_horiz).at(1)); // the other person's
  await tester.pumpAndSettle();
  await tester.tap(find.text('Report'));
  await tester.pumpAndSettle();
}

Future<void> _openPostReport(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Report'));
  await tester.pumpAndSettle();
}

/// Every SemanticsService.announce message, in order.
List<String> _announcements(WidgetTester tester) {
  final said = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final event = message as Map<Object?, Object?>;
      if (event['type'] == 'announce') {
        said.add((event['data'] as Map<Object?, Object?>)['message'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      null,
    ),
  );
  return said;
}

void main() {
  testWidgets('compose and quote: "Need support now?" opens Support, counted', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    var h = await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
      overrides: _on,
    );
    await tester.tap(find.text('Need support now?'));
    await tester.pumpAndSettle();
    expect(find.text('at /safety-resources'), findsOneWidget);
    expect(h.metrics, ['support_link_opened:opinions']);

    h = await pumpOpinionScreen(
      tester,
      () => QuoteComposeScreen(quotedOpinion: w9Opinion()),
      repo: repo,
      overrides: _on,
    );
    expect(find.text('Need support now?'), findsOneWidget);
  });

  testWidgets('the post menu: "Need support now?" first; the menu closes', (
    tester,
  ) async {
    final h = await _thread(tester, FakeOpinionRepository());
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    final support = find.text('Need support now?');
    final report = find.text('Report');
    expect(
      tester.getTopLeft(support).dy,
      lessThan(tester.getTopLeft(report).dy),
    );
    await tester.tap(support);
    await tester.pumpAndSettle();
    expect(find.text('at /safety-resources'), findsOneWidget);
    expect(h.metrics, ['support_link_opened:opinions']);
    // The menu closed first: nothing of it waits under Support (M-1).
    expect(find.text('Report', skipOffstage: false), findsNothing);
    expect(find.text('Copy text', skipOffstage: false), findsNothing);
  });

  // M-12: the feed card's menu is the same OpinionMoreData.
  testWidgets('the feed card menu: "Need support now?" first', (tester) async {
    await pumpOpinionScreen(
      tester,
      () => Scaffold(
        body: ListView(children: [OpinionCard(opinion: w9Opinion())]),
      ),
      repo: FakeOpinionRepository(),
      overrides: _on,
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Need support now?')).dy,
      lessThan(tester.getTopLeft(find.text('Report')).dy),
    );
  });

  // I-1 (spec §2.2): the report sheet holding the at-risk reason is in
  // place on its first frame, never sliding up.
  testWidgets('the post report sheet is never animated', (tester) async {
    await _thread(tester, FakeOpinionRepository());
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pump();
    final atRisk = find.text('Someone may be at risk');
    expect(atRisk.hitTestable(), findsOneWidget);
    final first = tester.getTopLeft(atRisk);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(atRisk), first);
  });

  testWidgets('every comment menu has it, mine and others', (tester) async {
    await _thread(tester, FakeOpinionRepository());
    for (final i in [0, 1]) {
      await tapInReach(tester, find.byIcon(Icons.more_horiz).at(i));
      await tester.pumpAndSettle();
      expect(
        find.text('Need support now?'),
        findsOneWidget,
        reason: 'comment $i',
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byIcon(Icons.more_horiz).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Need support now?'));
    await tester.pumpAndSettle();
    expect(find.text('at /safety-resources'), findsOneWidget);
  });

  testWidgets(
    'a post reported "Someone may be at risk": sent, thanked, numbers offered',
    (tester) async {
      final repo = FakeOpinionRepository();
      final h = await _thread(tester, repo);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      final atRisk = find.text('Someone may be at risk');
      expect(
        tester.getTopLeft(atRisk).dy,
        lessThan(tester.getTopLeft(find.text('Identifies a real person')).dy),
      );
      await tester.tap(atRisk);
      await tester.pump(); // never animated: in place at once
      await tester.pump();
      expect(find.text(_thanks), findsOneWidget);
      expect(tester.getRect(find.text(_thanks)).bottom, lessThanOrEqualTo(844));
      expect(repo.reports, ['opinion:o1:Someone may be at risk']);
      expect(find.text(_old24h), findsNothing);
      await tapInReach(tester, find.text('See emergency numbers'));
      await tester.pumpAndSettle();
      expect(find.text('at /safety-resources'), findsOneWidget);
      expect(h.metrics, ['support_link_opened:opinions']);
    },
  );

  testWidgets('a comment reported "Someone may be at risk": sent and thanked', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    await _thread(tester, repo);
    await _openCommentReport(tester);
    await tester.tap(find.text('Someone may be at risk'));
    await tester.pumpAndSettle();
    expect(repo.reports, ['comment:c-other:Someone may be at risk']);
    expect(find.text(_thanks), findsOneWidget);
    await tapInReach(tester, find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text(_thanks), findsNothing);
  });

  testWidgets('an at-risk report that fails says so', (tester) async {
    final said = _announcements(tester);
    final repo = FakeOpinionRepository()..refuseWith = Exception('offline');
    await _thread(tester, repo);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Someone may be at risk'));
    await tester.pumpAndSettle();
    expect(find.text(_failed), findsOneWidget);
    expect(find.text(_thanks), findsNothing);
    // Announced, with an icon beside the words (never colour alone).
    expect(said, [_failed]);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.byIcon(Icons.error_outline),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed at-risk comment report says so too', (tester) async {
    final repo = FakeOpinionRepository()..refuseWith = Exception('offline');
    await _thread(tester, repo);
    await _openCommentReport(tester);
    await tester.tap(find.text('Someone may be at risk'));
    await tester.pumpAndSettle();
    expect(repo.reports, ['comment:c-other:Someone may be at risk']);
    expect(find.text(_failed), findsOneWidget);
    expect(find.text(_thanks), findsNothing);
  });

  // Owner ruling (c): behind the flag, every comment reason reaches the
  // server; the thanks promises only that it was sent (review queue v0
  // lists only priority reasons, so no time is promised).
  testWidgets('every comment report reason reaches the server (ruling (c))', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    await _thread(tester, repo);
    for (final reason in _sixReasons) {
      await _openCommentReport(tester);
      await tapInReach(tester, find.text(reason));
      await tester.pumpAndSettle();
      expect(repo.reports.last, 'comment:c-other:$reason');
      expect(find.text(_sent), findsOneWidget, reason: reason);
      expect(find.text(_old24h), findsNothing, reason: reason);
      expect(find.text(_thanks), findsNothing, reason: reason);
      ScaffoldMessenger.of(
        tester.element(find.byType(CommentThreadScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    expect(repo.reports.length, 6);
  });

  testWidgets('a post reported for another reason: sent, no time promised', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    await _thread(tester, repo);
    await _openPostReport(tester);
    await tapInReach(tester, find.text('Spam'));
    await tester.pumpAndSettle();
    expect(repo.reports, ['opinion:o1:Spam']);
    expect(find.text(_sent), findsOneWidget);
    expect(find.text(_old24h), findsNothing);
  });

  testWidgets('another reason that fails says so, post and comment', (
    tester,
  ) async {
    final said = _announcements(tester);
    final repo = FakeOpinionRepository()..refuseWith = Exception('offline');
    await _thread(tester, repo);
    await _openPostReport(tester);
    // Seven reasons: the last is below the sheet's fold, a scroll away.
    await tester.ensureVisible(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(find.text(_failed), findsOneWidget);
    expect(find.text(_sent), findsNothing);
    ScaffoldMessenger.of(
      tester.element(find.byType(CommentThreadScreen)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await _openCommentReport(tester);
    await tapInReach(tester, find.text('Spam'));
    await tester.pumpAndSettle();
    expect(find.text(_failed), findsOneWidget);
    expect(find.text(_sent), findsNothing);
    expect(repo.reports, ['opinion:o1:Other', 'comment:c-other:Spam']);
    expect(said, [_failed, _failed]);
  });

  testWidgets('both report lists let large text through and scroll at 2.0', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    await _thread(tester, repo, textScale: 2.0);
    double scaleOf(String text) =>
        MediaQuery.textScalerOf(tester.element(find.text(text))).scale(10) / 10;

    await _openPostReport(tester);
    expect(scaleOf('Someone may be at risk'), 2.0);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(repo.reports, ['opinion:o1:Other']);
    ScaffoldMessenger.of(
      tester.element(find.byType(CommentThreadScreen)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await _openCommentReport(tester);
    expect(scaleOf('Someone may be at risk'), 2.0);
    expect(scaleOf('Report this comment'), 2.0);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(repo.reports, ['opinion:o1:Other', 'comment:c-other:Other']);
    // The thanks and the failure let large text through too.
    expect(scaleOf(_sent), 2.0);
  });

  testWidgets('the link and the thanks: guidelines and goldens', (
    tester,
  ) async {
    Widget link() => const Scaffold(body: Center(child: NeedSupportLink()));
    await pumpFlowScreen(tester, link);
    await expectFlowGuidelines(tester);
    // Flush at the screen's edge the tap-target guideline skips the link,
    // so its size is pinned here too.
    expect(
      _buttonSize(tester, 'Need support now?').height,
      greaterThanOrEqualTo(48),
    );
    await expectFlowGoldens(tester, 'need_support_link', link);

    Widget thanks() => Scaffold(
      body: Consumer(
        builder:
            (context, ref, _) => Center(
              child: TextButton(
                onPressed: () => showAtRiskReportThanks(context, ref),
                child: const Text('open'),
              ),
            ),
      ),
    );
    Future<void> open(WidgetTester t) async {
      await t.tap(find.text('open'));
      await t.pump();
    }

    await pumpFlowScreen(tester, thanks);
    await open(tester);
    await expectFlowGuidelines(tester);
    for (final label in ['See emergency numbers', 'Close']) {
      final size = _buttonSize(tester, label);
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
    }
    await expectFlowGoldens(tester, 'at_risk_thanks', thanks, before: open);
  });

  // Carry: at least 4.5:1 in light and in dark (the app's light
  // error/onError pair is 3.68:1, so the failure never uses it).
  for (final (name, theme) in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('link, thanks, sent and failed meet the guidelines ($name)', (
      tester,
    ) async {
      Widget screen() => Theme(
        data: theme,
        child: Scaffold(
          body: Consumer(
            builder:
                (context, ref, _) => Padding(
                  // As in compose: away from the screen's edge, where the
                  // tap-target guideline would skip the link.
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const NeedSupportLink(),
                      // The triggers are the test's own, in onSurface.
                      _Trigger(
                        'thanks',
                        () => showAtRiskReportThanks(context, ref),
                      ),
                      _Trigger('sent', () => sendReport(context, () async {})),
                      _Trigger('failed', () => showReportFailed(context)),
                    ],
                  ),
                ),
          ),
        ),
      );
      await pumpFlowScreen(tester, screen);
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.tap(find.text('sent'));
      await tester.pumpAndSettle();
      expect(find.text(_sent), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.text('failed'));
      await tester.pumpAndSettle();
      expect(find.text(_failed), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.tap(find.text('thanks'));
      await tester.pump();
      expect(find.text(_thanks), findsOneWidget);
      await expectFlowGuidelines(tester);
    });
  }

  // The thanks sizes to its content (not the 9/16 sheet cap), so at large
  // text "See emergency numbers" is in reach without a scroll. (Under the
  // test font, 2.0 fills the screen with the words alone: pinned at 1.5,
  // where the 9/16 cap would hide the button.)
  testWidgets('at large text the emergency numbers stay in reach', (
    tester,
  ) async {
    Widget thanks() => Scaffold(
      body: Consumer(
        builder:
            (context, ref, _) => Center(
              child: TextButton(
                onPressed: () => showAtRiskReportThanks(context, ref),
                child: const Text('open'),
              ),
            ),
      ),
    );
    await pumpFlowScreen(tester, thanks, textScale: 1.5);
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.text('See emergency numbers').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // M-2: what a tap sends follows the list that was shown, even if the
  // flag is re-read (a resume) while the list is open.
  testWidgets('the comment list and its tap agree when the flag changes', (
    tester,
  ) async {
    final flag = StateProvider<bool>((ref) => true);
    final repo = FakeOpinionRepository();
    final opinion = w9Opinion();
    await pumpOpinionScreen(
      tester,
      () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
      repo: repo,
      overrides: [
        opinionsSafetyProvider.overrideWith((ref) => ref.watch(flag)),
      ],
    );
    await _openCommentReport(tester);
    expect(find.text('Someone may be at risk'), findsOneWidget);
    ProviderScope.containerOf(tester.element(find.byType(CommentThreadScreen)))
        .read(flag.notifier)
        .state = false;
    await tester.pump();
    await tapInReach(tester, find.text('Spam'));
    await tester.pumpAndSettle();
    expect(repo.reports, ['comment:c-other:Spam']);
    expect(find.text(_sent), findsOneWidget);
  });

  // M-3 (§2.2): a slow report says it is sending after 400 ms, and the
  // reporter hears back even when the card that sent it is gone.
  for (final fails in [false, true]) {
    testWidgets('a slow at-risk report: "Sending" at 400 ms, then '
        '${fails ? 'the failure' : 'the thanks'}, sender gone', (tester) async {
      final reply = Completer<void>();
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      Widget screen() => Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder:
              (_, show, __) =>
                  show
                      ? Consumer(
                        builder:
                            (context, ref, _) => Center(
                              child: TextButton(
                                onPressed:
                                    () => sendAtRiskReport(
                                      context,
                                      ref,
                                      () => reply.future,
                                    ),
                                child: const Text('report'),
                              ),
                            ),
                      )
                      : const SizedBox(),
        ),
      );
      final h = await pumpFlowScreen(tester, screen);
      await tester.tap(find.text('report'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Sending your report'), findsNothing);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Sending your report'), findsOneWidget);
      visible.value = false; // the card scrolls away mid-call
      await tester.pump();
      expect(find.text('report'), findsNothing);
      if (fails) {
        reply.completeError(Exception('offline'));
      } else {
        reply.complete();
      }
      await tester.pumpAndSettle();
      expect(find.text(_failed), fails ? findsOneWidget : findsNothing);
      expect(find.text(_thanks), fails ? findsNothing : findsOneWidget);
      expect(find.text('Sending your report'), findsNothing);
      if (!fails) {
        await tapInReach(tester, find.text('See emergency numbers'));
        await tester.pumpAndSettle();
        expect(find.text('at /safety-resources'), findsOneWidget);
        expect(h.metrics, ['support_link_opened:opinions']);
      }
    });
  }

  testWidgets('a fast report never says "Sending"', (tester) async {
    final repo = FakeOpinionRepository();
    await _thread(tester, repo);
    await _openCommentReport(tester);
    await tapInReach(tester, find.text('Spam'));
    await tester.pumpAndSettle();
    expect(find.text(_sent), findsOneWidget);
    expect(find.text('Sending your report'), findsNothing);
  });

  // PF-C8: one path for an at-risk report from either list.
  testWidgets('sendAtRiskReport: sent then thanked; refused then told', (
    tester,
  ) async {
    var calls = 0;
    Object? refuse;
    Widget screen() => Scaffold(
      body: Consumer(
        builder:
            (context, ref, _) => Center(
              child: TextButton(
                onPressed:
                    () => sendAtRiskReport(context, ref, () async {
                      calls++;
                      if (refuse != null) throw refuse;
                    }),
                child: const Text('report'),
              ),
            ),
      ),
    );
    await pumpFlowScreen(tester, screen);
    await tester.tap(find.text('report'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text(_thanks), findsOneWidget);
    expect(find.text(_failed), findsNothing);
    await tapInReach(tester, find.text('Close'));
    await tester.pumpAndSettle();

    refuse = Exception('offline');
    await tapInReach(tester, find.text('report'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text(_thanks), findsNothing);
    expect(find.text(_failed), findsOneWidget);
  });

  // P-19: read from app start (menus read it once, as they open) and again
  // on resume, with no screen watching it.
  testWidgets('the refresher reads the flag at start and on resume', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          opinionsSafetyReadProvider.overrideWith((ref) async {
            reads++;
            return true;
          }),
        ],
        child: const MaterialApp(home: FeatureFlagRefresher(child: SizedBox())),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, 2);
  });

  test('the manual passage shows only with the flag', () {
    expect(
      DocumentationRegistry.passageVisible('opinionsSafety', const {}),
      isFalse,
    );
    expect(
      DocumentationRegistry.passageVisible('opinionsSafety', const {
        'opinions_safety_v1',
      }),
      isTrue,
    );
  });
}

class _Trigger extends StatelessWidget {
  const _Trigger(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

/// The size of the button whose label is [label].
Size _buttonSize(WidgetTester tester, String label) => tester.getSize(
  find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  ),
);
