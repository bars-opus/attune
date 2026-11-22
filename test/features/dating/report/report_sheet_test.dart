// Spec 2 W7a Task 3 (§3.5, §3.6, §3.7, §3.15 Report sheet; R-43; D8; W6
// carry T4): the answers fail closed; the repository sends its one RPC
// per target; the sheet: 14 labelled categories, "Also block" on for P0 to
// P2 until touched, the 500-character field, nothing sent offline, one
// key per report (a busy retry is the same request), the thanks with the
// review time or the testing line and the emergency number, the money
// line with Pause Dating; Report reaches the Safety sheet (first), each
// safety card (the reported card leaves the chat at once), the ended list
// and the card's More on Today; another account sees nothing of an open
// sheet; goldens at 1.0, 1.3, 2.0 and RTL; the three guidelines.

import 'dart:io';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/dating_report_repository.dart';
import 'package:attune/features/dating/report/report_sheet.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

const _card = DatingSafetyCard(
  id: 'e1',
  messageId: 'd2',
  family: 'financial_request',
);

void main() {
  final loc = AppLocalizationsEn();

  test('the answers fail closed; the categories are §3.7\'s', () {
    expect(
      DatingReportAnswer.fromJson({
        'ok': true,
        'review': 'testing',
        'sla_hours': 48,
      }).slaHours,
      48,
    );
    expect(
      DatingReportAnswer.fromJson({'ok': true, 'review': 'staffed'}).testing,
      isFalse,
    );
    expect(DatingReportAnswer.fromJson({'ok': true}).testing, isTrue);
    for (final r in ['rate_limited', 'report_unavailable', 'invalid']) {
      expect(DatingReportAnswer.fromJson({'ok': false, 'reason': r}).reason, r);
    }
    expect(
      DatingReportAnswer.fromJson({
        'ok': false,
        'reason': 'Kofi blocked',
      }).reason,
      'failed',
    );
    expect(DatingReportAnswer.fromJson('x').reason, 'failed');
    // W7a Task 1/2 fixes: busy is an answer too; "blocked": false says the
    // "Also block" step didn't go through (no key: it did, or none asked).
    expect(
      DatingReportAnswer.fromJson({'ok': false, 'reason': 'busy'}).reason,
      'busy',
    );
    expect(
      DatingReportAnswer.fromJson({'ok': true, 'blocked': false}).blocked,
      isFalse,
    );
    expect(DatingReportAnswer.fromJson({'ok': true}).blocked, isTrue);
    // Task 2 fix round: the restriction read can answer busy (retryable).
    expect(
      DatingRestrictionRead.fromJson({'ok': false, 'reason': 'busy'}).reason,
      'busy',
    );
    expect(
      DatingRestrictionRead.fromJson({'ok': false, 'reason': 'x'}).reason,
      'failed',
    );
    expect(DatingRestrictionRead.fromJson(null).reason, 'failed');
    final rejected = DatingRestrictionRead.fromJson({
      'ok': true,
      'restriction': {
        'id': 'r1',
        'type': 'suspended',
        'can_appeal': false,
        'appeal': {'state': 'rejected'},
      },
    });
    expect(rejected.restriction!.canAppeal, isFalse);
    expect(rejected.restriction!.appeal!.state, DatingAppealState.rejected);
    expect(
      DatingReportAnswer.fromJson({'ok': true, 'blocked': 'no'}).blocked,
      isTrue,
    );
    expect(DatingReportCategory.values.map((c) => c.wire), [
      'underage_risk',
      'csam',
      'child_safety',
      'threat_to_life',
      'sextortion',
      'romance_scam',
      'threats',
      'entrapment',
      'harassment',
      'explicit_content',
      'impersonation',
      'hiding_relationship',
      'spam',
      'other',
    ]);
    expect(
      DatingReportCategory.values.where((c) => c.blockByDefault).length,
      12,
    );
    expect(DatingReportCategory.spam.blockByDefault, isFalse);
  });

  test('the repository sends one RPC per target, with the toggle', () async {
    final calls = <(String, Map<String, dynamic>?)>[];
    final repo = DatingReportRepository(
      DatingRpc.withCall((fn, params) async {
        calls.add((fn, params));
        return {'ok': true, 'review': 'testing', 'sla_hours': 4};
      }),
    );
    await repo.report(
      'k1',
      const DatingReportMatch('m1'),
      DatingReportCategory.csam,
      null,
      alsoBlock: true,
    );
    await repo.report(
      'k2',
      const DatingReportCard('i1'),
      DatingReportCategory.spam,
      'x',
      alsoBlock: false,
    );
    await repo.appeal('k3', 'r1', 'Why');
    await repo.restriction();
    expect(calls.map((c) => c.$1), [
      'report_dating_match',
      'report_dating_introduction',
      'submit_dating_appeal',
      'get_my_dating_restriction',
    ]);
    expect(calls[0].$2, {
      'p_idempotency_key': 'k1',
      'p_match_id': 'm1',
      'p_category': 'csam',
      'p_details': null,
      'p_also_block': true,
    });
    expect(calls[1].$2!['p_introduction_id'], 'i1');
    expect(calls[2].$2, {
      'p_idempotency_key': 'k3',
      'p_restriction_id': 'r1',
      'p_text': 'Why',
    });
  });

  Future<DatingShell> chat(
    WidgetTester t,
    FakeDatingReport report, {
    FakeDatingChat? fake,
    bool online = true,
    bool emergency = true,
  }) => pumpDatingShell(
    t,
    initial: '/dating/chat/m1',
    online: online,
    overrides: [
      ...datingChatOverrides(fake ?? FakeDatingChat()),
      ...datingReportOverrides(report, emergency: emergency),
    ],
  );

  Future<void> openReport(WidgetTester t) async {
    await tap(t, find.bySemanticsLabel(loc.dating_chatSafetyLabel));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportTitle('Kofi')));
    await t.pumpAndSettle();
  }

  testWidgets('the Safety sheet offers Report first; the sheet sends one '
      'report with the toggle on for P0-P2 until touched, and thanks with '
      'the testing line and the number', (t) async {
    final report = FakeDatingReport();
    await chat(t, report);
    await tap(t, find.bySemanticsLabel(loc.dating_chatSafetyLabel));
    await t.pumpAndSettle();
    final first = t.getTopLeft(find.text(loc.dating_reportTitle('Kofi')));
    final block = t.getTopLeft(find.text(loc.dating_blockRow('Kofi')));
    expect(first.dy, lessThan(block.dy));
    await tap(t, find.text(loc.dating_reportTitle('Kofi')));
    await t.pumpAndSettle();
    for (final c in DatingReportCategory.values) {
      expect(find.text(datingReportLabel(loc, c)), findsOneWidget);
    }
    Switch toggle() => t.widget<Switch>(
      find.descendant(
        of: find.byKey(const ValueKey('dating_report_block')),
        matching: find.byType(Switch),
      ),
    );
    final send = find.byKey(const ValueKey('dating_report_send'));
    await tap(t, send);
    expect(report.reports, isEmpty, reason: 'no category, nothing sent');
    await tap(t, find.text(loc.dating_reportSpam));
    expect(toggle().value, isFalse);
    await tap(t, find.text(loc.dating_reportHarassment));
    expect(toggle().value, isTrue);
    await tap(t, find.byKey(const ValueKey('dating_report_block')));
    await tap(t, find.text(loc.dating_reportThreatToLife));
    expect(toggle().value, isFalse, reason: 'a touched toggle stays put');
    await t.enterText(
      find.byKey(const ValueKey('dating_report_details')),
      '  He kept writing.  ',
    );
    await tap(t, send);
    await t.pumpAndSettle();
    expect(report.reports, hasLength(1));
    final r = report.reports.single;
    expect(r.target, isA<DatingReportMatch>());
    expect(r.target.id, 'm1');
    expect(r.category, DatingReportCategory.threatToLife);
    expect(r.details, 'He kept writing.');
    expect(r.alsoBlock, isFalse);
    expect(find.text(loc.dating_reportSentTitle), findsOneWidget);
    expect(find.text(loc.dating_reportSentTesting('112')), findsOneWidget);
  });

  testWidgets('staffed: the review time in words; no emergency entry: the '
      'local line; a money report adds its line and pauses Dating', (t) async {
    final report =
        FakeDatingReport()
          ..answer = const DatingReportAnswer(
            ok: true,
            testing: false,
            slaHours: 24,
          );
    final shell = await chat(t, report, emergency: false);
    await openReport(t);
    await tap(t, find.text(loc.dating_reportMoney));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(
      find.text(loc.dating_reportSentNoNumber(loc.dating_reportHours(24))),
      findsOneWidget,
    );
    expect(find.text(loc.dating_reportScam), findsOneWidget);
    // W7 final client fix (I-2): paused only when the server says so.
    shell.life.result = const DatingLifecycleResult.done('paused');
    await tap(t, find.byKey(const ValueKey('dating_report_pause')));
    await t.pumpAndSettle();
    expect(shell.life.calls, ['pause']);
    expect(find.text(loc.dating_pausedLine), findsOneWidget);
    expect(loc.dating_reportDays(3), '3 days');
    expect(loc.dating_reportHours(1), '1 hour');
  });

  testWidgets('offline nothing is sent; busy keeps the key, so the retry '
      'is the same report; a refusal is its own line', (t) async {
    final report = FakeDatingReport();
    await chat(t, report, online: false);
    await openReport(t);
    await tap(t, find.text(loc.dating_reportSpam));
    expect(find.text(loc.dating_reportOffline), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    expect(report.reports, isEmpty);

    final busy = FakeDatingReport()..answer = DatingReportAnswer.busy;
    await chat(t, busy);
    await openReport(t);
    await tap(t, find.text(loc.dating_reportSpam));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_busy), findsOneWidget);
    busy.answer = const DatingReportAnswer(ok: false, reason: 'rate_limited');
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(busy.reports, hasLength(2));
    expect(busy.reports[1].key, busy.reports[0].key);
    expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
  });

  testWidgets('a reported safety card leaves the chat at once, by id, and '
      'its dismissal is sent; with "Also block" the chat is ended here', (
    t,
  ) async {
    final fake = FakeDatingChat()..cardList = const [_card];
    final report = FakeDatingReport();
    await chat(t, report, fake: fake);
    expect(find.byKey(const ValueKey('dating_card_e1')), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_card_report')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportMoney));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    await tap(t, find.byKey(const ValueKey('dating_report_close')));
    await t.pumpAndSettle();
    expect(report.reports.single.alsoBlock, isTrue);
    expect(find.byKey(const ValueKey('dating_card_e1')), findsNothing);
    expect(fake.dismissed, contains('e1'));
    expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
  });

  testWidgets('"Also block" that didn\'t go through: the sheet says so, '
      'and the chat still offers Block (it is not shown blocked)', (t) async {
    final report =
        FakeDatingReport()
          ..answer = const DatingReportAnswer(ok: true, blocked: false);
    await chat(t, report);
    await openReport(t);
    await tap(t, find.text(loc.dating_reportHarassment));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(report.reports.single.alsoBlock, isTrue);
    expect(find.text(loc.dating_reportNotBlocked('Kofi')), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_report_close')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_blockDone('Kofi')), findsNothing);
    await tap(t, find.bySemanticsLabel(loc.dating_chatSafetyLabel));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_blockRow('Kofi')), findsOneWidget);
  });

  testWidgets('a sent report is the outcome however the sheet closes, and '
      'the lock (or quick exit) closes an open one sending nothing', (t) async {
    final fake = FakeDatingChat()..cardList = const [_card];
    final report = FakeDatingReport();
    await chat(t, report, fake: fake);
    await tap(t, find.byKey(const ValueKey('dating_card_report')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportSpam));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportSentTitle), findsOneWidget);
    // Popped from outside the sheet (a drag down pops it this way).
    Navigator.of(t.element(find.text(loc.dating_reportSentTitle))).pop();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportSentTitle), findsNothing);
    expect(find.byKey(const ValueKey('dating_card_e1')), findsNothing);

    await openReport(t);
    expect(find.text(loc.dating_reportSend), findsOneWidget);
    closeDatingSheets();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportSend), findsNothing);
    expect(find.bySemanticsLabel(loc.dating_chatSafetyLabel), findsOneWidget);
    expect(report.reports, hasLength(1));
  });

  testWidgets('the ended list: its line, and only Report, for each row', (
    t,
  ) async {
    final fake = FakeDatingChat(
      list: datingConversationsJson(
        rows: const [],
        ended: [
          {
            'match_id': 'm9',
            'display_name': 'Yaw',
            'ended_at': '2026-11-19T10:00:00Z',
          },
        ],
      ),
    );
    final report = FakeDatingReport();
    await pumpDatingShell(
      t,
      initial: DatingPaths.chats,
      overrides: [
        ...datingChatOverrides(fake),
        ...datingReportOverrides(report),
      ],
    );
    expect(find.text(loc.dating_endedReportLine), findsOneWidget);
    expect(
      find.bySemanticsLabel(loc.dating_reportTitle('Yaw')),
      findsOneWidget,
    );
    await tap(t, find.byKey(const ValueKey('dating_chats_report_m9')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportSextortion));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(report.reports.single.target.id, 'm9');
    expect(report.reports.single.target, isA<DatingReportMatch>());
  });

  testWidgets('the card on Today: More offers Report, which reports the '
      'introduction', (t) async {
    final today = FakeDatingToday();
    final report = FakeDatingReport();
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: [
        ...datingTodayOverrides(today),
        ...datingReportOverrides(report),
      ],
    );
    await tapInReach(t, find.text(loc.dating_cardMore));
    await t.pumpAndSettle();
    await tapInReach(t, find.text(loc.dating_reportTitle('Kofi')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportSpam));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(report.reports.single.target, isA<DatingReportCard>());
    expect(report.reports.single.alsoBlock, isFalse);
  });

  testWidgets('the card on Today: a report with "Also block" collapses the '
      'card as Block does; one whose block didn\'t go through leaves it', (
    t,
  ) async {
    final today = FakeDatingToday();
    final report =
        FakeDatingReport()
          ..answer = const DatingReportAnswer(ok: true, blocked: false);
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: [
        ...datingTodayOverrides(today),
        ...datingReportOverrides(report),
      ],
    );
    Future<void> reportHarassment() async {
      await tapInReach(t, find.text(loc.dating_cardMore));
      await t.pumpAndSettle();
      await tapInReach(t, find.text(loc.dating_reportTitle('Kofi')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_reportHarassment));
      await tap(t, find.byKey(const ValueKey('dating_report_send')));
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('dating_report_close')));
      await t.pumpAndSettle();
    }

    await reportHarassment();
    expect(report.reports.single.target, isA<DatingReportCard>());
    expect(report.reports.single.alsoBlock, isTrue);
    expect(find.text(loc.dating_blockDone('Kofi')), findsNothing);
    expect(find.text(loc.dating_cardMore), findsWidgets);
    expect(today.blocks, isEmpty, reason: 'the report blocks, never Today');

    report.answer = const DatingReportAnswer(ok: true, slaHours: 48);
    await reportHarassment();
    expect(report.reports, hasLength(2));
    expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
    expect(today.blocks, isEmpty);
  });

  testWidgets('the card\'s More answers once: a second tap on Block while '
      'it closes never turns Report into Block', (t) async {
    final report = FakeDatingReport();
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: [
        ...datingTodayOverrides(FakeDatingToday()),
        ...datingReportOverrides(report),
      ],
    );
    await tapInReach(t, find.text(loc.dating_cardMore));
    await t.pumpAndSettle();
    // Both rows' taps land before the sheet has closed (no frame between).
    InfoRowWidget row(String title) => t.widget<InfoRowWidget>(
      find.ancestor(of: find.text(title), matching: find.byType(InfoRowWidget)),
    );
    final report0 = row(loc.dating_reportTitle('Kofi'));
    final block0 = row(loc.dating_blockRow('Kofi'));
    report0.onTap!();
    block0.onTap!();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportSend), findsOneWidget);
    expect(find.text(loc.dating_blockTitle('Kofi')), findsNothing);
  });

  testWidgets('D8: another account sees nothing of an open report sheet, '
      'which closes sending nothing', (t) async {
    final report = FakeDatingReport();
    final shell = await chat(t, report);
    await openReport(t);
    expect(find.text(loc.dating_reportSend), findsOneWidget);
    await tap(t, find.text(loc.dating_reportSpam));
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    expect(find.text(loc.dating_reportSend), findsNothing);
    expect(find.text(loc.dating_reportSpam), findsNothing);
    await t.pumpAndSettle();
    expect(report.reports, isEmpty);
  });

  testWidgets('the sheet: goldens at 1.0, 1.3, 2.0 and RTL; the three '
      'guidelines; the sent state too', (t) async {
    final report = FakeDatingReport();
    // Fix round 1 (I-3): as showDatingReportSheet shows it, under
    // AllowLargeText, so the 1.3 and 2.0 goldens really grow.
    Widget screen() => Consumer(
      builder:
          (context, ref, _) => const AllowLargeText(
            child: Scaffold(
              body: DatingReportSheet(
                account: 'ama',
                name: 'Kofi',
                target: DatingReportMatch('m1'),
              ),
            ),
          ),
    );
    final overrides = [
      ...datingShellOverrides(),
      ...datingReportOverrides(report),
    ];
    await expectFlowGoldens(
      t,
      'dating_report_sheet',
      screen,
      overrides: overrides,
    );
    await pumpFlowScreen(t, screen, overrides: overrides);
    await expectFlowGuidelines(t);
    await tap(t, find.text(loc.dating_reportHarassment));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dating_report_sheet.sent.png'),
    );
    await expectFlowGuidelines(t);
  });

  testWidgets('the sheet in dark: a refusal in the theme\'s error red, then '
      'the sent state with the money line and a block that didn\'t go '
      'through (goldens)', (t) async {
    final report =
        FakeDatingReport()
          ..answer = const DatingReportAnswer(
            ok: false,
            reason: 'rate_limited',
          );
    await pumpFlowScreen(
      t,
      () => Theme(
        data: AppTheme.darkTheme,
        child: const AllowLargeText(
          child: Scaffold(
            body: DatingReportSheet(
              account: 'ama',
              name: 'Kofi',
              target: DatingReportMatch('m1'),
            ),
          ),
        ),
      ),
      size: const Size(390, 1500),
      overrides: [...datingShellOverrides(), ...datingReportOverrides(report)],
    );
    await tap(t, find.text(loc.dating_reportMoney));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dating_report_sheet.dark_error.png'),
    );
    report.answer = const DatingReportAnswer(ok: true, blocked: false);
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportNotBlocked('Kofi')), findsOneWidget);
    expect(find.text(loc.dating_reportScam), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dating_report_sheet.dark_sent.png'),
    );
    await expectFlowGuidelines(t);
  });

  testWidgets('fix round 1 (I-3): the sent state in dark at 2.0 (golden); '
      'the 1.3 and 2.0 goldens are not the 1.0 one', (t) async {
    final report =
        FakeDatingReport()
          ..answer = const DatingReportAnswer(ok: true, blocked: false);
    await pumpFlowScreen(
      t,
      () => Theme(
        data: AppTheme.darkTheme,
        child: const AllowLargeText(
          child: Scaffold(
            body: DatingReportSheet(
              account: 'ama',
              name: 'Kofi',
              target: DatingReportMatch('m1'),
            ),
          ),
        ),
      ),
      textScale: 2.0,
      size: const Size(390, 3000),
      overrides: [...datingShellOverrides(), ...datingReportOverrides(report)],
    );
    await tap(t, find.text(loc.dating_reportMoney));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportNotBlocked('Kofi')), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dating_report_sheet.dark_sent_scale2.0.png'),
    );
    const dir = 'test/features/dating/report/goldens/dating_report_sheet';
    final one = File('$dir.scale1.0.png').readAsBytesSync();
    for (final scale in ['1.3', '2.0']) {
      expect(
        File('$dir.scale$scale.png').readAsBytesSync(),
        isNot(equals(one)),
        reason: 'scale $scale drawn at 1.0',
      );
    }
  });
}
