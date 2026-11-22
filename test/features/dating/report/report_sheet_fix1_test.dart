// Spec 2 W7a Task 3 fix round 1 (task-3-review.md): I-1 a report on its way
// survives the sheet: back, the barrier and a drag do nothing while it is
// out (the sending state shows), a pop from outside still hands the
// screen its outcome, and a sheet opened again after a busy answer sends
// the same request (one key per account and target, never a second
// report); I-2 a P0 report from a card on Today without "Also block"
// takes the card away (the server invalidates it, R-63) and Today reads
// again; I-4 the details field counts code points as the server does;
// M-1 a production answer without its hours (or a replay) never says "In
// testing"; M-2 the ended list's not-blocked line promises no retry; M-3
// "What happened?" is read once; M-4/M-5 the emergency number is a call
// (S1's confirm first) on the thanks and under every refusal; M-6 the
// in-flight state, the days branch, report_unavailable, the support read
// failing and a pause failing; M-7 one live region in the thanks.
import 'dart:async';

import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  final send = find.byKey(const ValueKey('dating_report_send'));

  Future<DatingShell> chat(
    WidgetTester t,
    FakeDatingReport report, {
    FakeDatingChat? fake,
    bool emergency = true,
    List<Override> extra = const [],
  }) => pumpDatingShell(
    t,
    initial: '/dating/chat/m1',
    overrides: [
      ...datingChatOverrides(fake ?? FakeDatingChat()),
      ...datingReportOverrides(report, emergency: emergency),
      ...extra,
    ],
  );

  Future<void> openReport(WidgetTester t) async {
    await tap(t, find.bySemanticsLabel(loc.dating_chatSafetyLabel));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportTitle('Kofi')));
    await t.pumpAndSettle();
  }

  group('I-1: a report on its way', () {
    testWidgets('back, the barrier and a drag do nothing while it is out; '
        'the sending state shows; a second Send sends nothing; the thanks '
        'comes, and the reported card leaves', (t) async {
      final fake = FakeDatingChat()..cardList = const [_card];
      final report = FakeDatingReport()..hold = Completer<void>();
      await chat(t, report, fake: fake);
      // Tall enough that the barrier shows above the whole sheet.
      t.view.physicalSize = const Size(390, 2600);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('dating_card_report')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_reportSpam));
      await tap(t, send);
      // FlowPrimaryButton's ring shows past 400 ms.
      await t.pump(const Duration(milliseconds: 200));
      expect(report.reports, hasLength(1));
      // The sending state: the button busy, the choices and field off.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        t
            .widget<RadioListTile<DatingReportCategory>>(
              find.byKey(const ValueKey('dating_report_spam')),
            )
            .onChanged,
        isNull,
      );
      expect(
        t
            .widget<TextField>(
              find.byKey(const ValueKey('dating_report_details')),
            )
            .enabled,
        isFalse,
      );
      await t.tap(send, warnIfMissed: false);
      await t.pump();
      expect(report.reports, hasLength(1), reason: 'one report on its way');

      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(loc.dating_reportWhat), findsOneWidget, reason: 'back');
      await t.tapAt(const Offset(195, 20));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(loc.dating_reportWhat), findsOneWidget, reason: 'tap');
      await t.drag(
        find.text(loc.dating_reportTitle('Kofi')),
        const Offset(0, 900),
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(loc.dating_reportWhat), findsOneWidget, reason: 'drag');

      report.hold!.complete();
      await t.pumpAndSettle();
      expect(find.text(loc.dating_reportSentTitle), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('dating_report_close')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dating_card_e1')), findsNothing);
      expect(fake.dismissed, contains('e1'));
    });

    testWidgets('popped from outside while it is out, the screen still '
        'gets the outcome once the answer lands', (t) async {
      final fake = FakeDatingChat()..cardList = const [_card];
      final report = FakeDatingReport()..hold = Completer<void>();
      await chat(t, report, fake: fake);
      await tap(t, find.byKey(const ValueKey('dating_card_report')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_reportMoney));
      await tap(t, send);
      Navigator.of(t.element(find.text(loc.dating_reportSend))).pop();
      await t.pumpAndSettle();
      expect(find.text(loc.dating_reportSend), findsNothing);
      expect(find.byKey(const ValueKey('dating_card_e1')), findsOneWidget);
      report.hold!.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dating_card_e1')), findsNothing);
      expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
    });

    testWidgets('a sheet opened again after busy sends the same request '
        '(no second report); a named refusal frees the key', (t) async {
      final report = FakeDatingReport()..answer = DatingReportAnswer.busy;
      await chat(t, report);
      await openReport(t);
      await tap(t, find.text(loc.dating_reportSpam));
      await tap(t, send);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_busy), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text(loc.dating_reportSend), findsNothing);
      await openReport(t);
      await tap(t, find.text(loc.dating_reportSpam));
      report.answer = const DatingReportAnswer(ok: true, slaHours: 72);
      await tap(t, send);
      await t.pumpAndSettle();
      expect(report.reports, hasLength(2));
      expect(report.reports[1].key, report.reports[0].key);
      await tap(t, find.byKey(const ValueKey('dating_report_close')));
      await t.pumpAndSettle();
      // Sent: the next report of the same person is a new request.
      await openReport(t);
      await tap(t, find.text(loc.dating_reportSpam));
      await tap(t, send);
      await t.pumpAndSettle();
      expect(report.reports, hasLength(3));
      expect(report.reports[2].key, isNot(report.reports[0].key));
    });
  });

  testWidgets('I-2: a P0 report from Today\'s card without "Also block" '
      'takes the card away (its photos too) and Today reads again', (t) async {
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
    expect(find.text(loc.dating_cardMore), findsOneWidget);
    final reads = today.reads;
    await tapInReach(t, find.text(loc.dating_cardMore));
    await t.pumpAndSettle();
    await tapInReach(t, find.text(loc.dating_reportTitle('Kofi')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportUnderage));
    await tap(t, find.byKey(const ValueKey('dating_report_block')));
    await tap(t, send);
    await t.pumpAndSettle();
    expect(report.reports.single.alsoBlock, isFalse);
    await tap(t, find.byKey(const ValueKey('dating_report_close')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_cardMore), findsNothing);
    expect(find.text(loc.dating_blockDone('Kofi')), findsNothing);
    expect(today.reads, greaterThan(reads));
  });

  testWidgets('I-2: a P2 report without "Also block" leaves the card', (
    t,
  ) async {
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
    await tap(t, find.text(loc.dating_reportHarassment));
    await tap(t, find.byKey(const ValueKey('dating_report_block')));
    await tap(t, send);
    await t.pumpAndSettle();
    await tap(t, find.byKey(const ValueKey('dating_report_close')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_cardMore), findsOneWidget);
  });

  testWidgets('I-4: the details field counts code points (emoji are two), '
      'as the server does', (t) async {
    final report = FakeDatingReport();
    await chat(t, report);
    await openReport(t);
    final field = find.byKey(const ValueKey('dating_report_details'));
    await t.enterText(field, '${'a' * 499}👍🏽👍🏽');
    await t.pump();
    final text = t.widget<TextField>(field).controller!.text;
    expect(text.runes.length, 500);
    expect(
      find.text(loc.dating_gentleWaitAnswerCount(500, 500)),
      findsOneWidget,
    );
    await tap(t, find.text(loc.dating_reportSpam));
    await tap(t, send);
    await t.pumpAndSettle();
    expect(report.reports.single.details!.runes.length, lessThanOrEqualTo(500));
  });

  group('M-1: the review line', () {
    for (final (name, answer) in [
      ('a replay ({ok: true})', DatingReportAnswer.fromJson({'ok': true})),
      (
        'staffed without its hours',
        DatingReportAnswer.fromJson({'ok': true, 'review': 'staffed'}),
      ),
    ]) {
      testWidgets('$name: no time, never "In testing"', (t) async {
        final report = FakeDatingReport()..answer = answer;
        await chat(t, report);
        await openReport(t);
        await tap(t, find.text(loc.dating_reportSpam));
        await tap(t, send);
        await t.pumpAndSettle();
        expect(find.text(loc.dating_reportSentNoTime('112')), findsOneWidget);
        expect(find.textContaining('In testing'), findsNothing);
      });
    }

    testWidgets('staffed 72 hours is "3 days"; 47 hours stays hours', (
      t,
    ) async {
      final report =
          FakeDatingReport()
            ..answer = DatingReportAnswer.fromJson({
              'ok': true,
              'review': 'staffed',
              'sla_hours': 72,
            });
      await chat(t, report);
      await openReport(t);
      await tap(t, find.text(loc.dating_reportSpam));
      await tap(t, send);
      await t.pumpAndSettle();
      expect(
        find.text(loc.dating_reportSent(loc.dating_reportDays(3), '112')),
        findsOneWidget,
      );
      await tap(t, find.byKey(const ValueKey('dating_report_close')));
      await t.pumpAndSettle();
      report.answer = DatingReportAnswer.fromJson({
        'ok': true,
        'review': 'staffed',
        'sla_hours': 47,
      });
      await openReport(t);
      await tap(t, find.text(loc.dating_reportSpam));
      await tap(t, send);
      await t.pumpAndSettle();
      expect(
        find.text(loc.dating_reportSent(loc.dating_reportHours(47), '112')),
        findsOneWidget,
      );
    });
  });

  testWidgets('M-2: from the ended list (no Block there), the not-blocked '
      'line promises no retry', (t) async {
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
    final report =
        FakeDatingReport()
          ..answer = const DatingReportAnswer(ok: true, blocked: false);
    await pumpDatingShell(
      t,
      initial: DatingPaths.chats,
      overrides: [
        ...datingChatOverrides(fake),
        ...datingReportOverrides(report),
      ],
    );
    await tap(t, find.byKey(const ValueKey('dating_chats_report_m9')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportHarassment));
    await tap(t, send);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportNotBlockedEnded('Yaw')), findsOneWidget);
    expect(find.text(loc.dating_reportNotBlocked('Yaw')), findsNothing);
  });

  testWidgets('M-3: "What happened?" is read once', (t) async {
    final handle = t.ensureSemantics();
    await chat(t, FakeDatingReport());
    await openReport(t);
    expect(find.bySemanticsLabel(loc.dating_reportWhat), findsOneWidget);
    handle.dispose();
  });

  testWidgets('M-4/M-5: the number is a call, after the confirm, on the '
      'thanks and under a refusal; a support read that fails says the '
      'local number', (t) async {
    final calls = <String>[];
    final report =
        FakeDatingReport()
          ..answer = const DatingReportAnswer(
            ok: false,
            reason: 'rate_limited',
          );
    await chat(
      t,
      report,
      extra: [
        supportLauncherProvider.overrideWithValue((context, url) async {
          calls.add(url);
        }),
      ],
    );
    await openReport(t);
    await tap(t, find.text(loc.dating_reportSpam));
    await tap(t, send);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
    expect(find.text(loc.dating_reportDanger('112')), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_report_call')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.support_callConfirmCall));
    await t.pumpAndSettle();
    expect(calls, ['tel:112']);
    // The sheet is still there after the call.
    expect(find.text(loc.dating_reportSend), findsOneWidget);
    report.answer = const DatingReportAnswer(ok: false, reason: 'busy');
    await tap(t, send);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportDanger('112')), findsOneWidget);
    report.answer = const DatingReportAnswer(ok: true, slaHours: 4);
    await tap(t, send);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportDanger('112')), findsNothing);
    await tap(t, find.byKey(const ValueKey('dating_report_call')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.support_callConfirmCall));
    await t.pumpAndSettle();
    expect(calls, ['tel:112', 'tel:112']);
  });

  testWidgets('M-5/M-6: report_unavailable has its line and the danger '
      'line; with the support read failing it is the local number and no '
      'call', (t) async {
    final report =
        FakeDatingReport()
          ..answer = const DatingReportAnswer(
            ok: false,
            reason: 'report_unavailable',
          );
    await chat(
      t,
      report,
      extra: [
        supportResourcesProvider.overrideWith(
          (ref, country) async => throw StateError('offline'),
        ),
      ],
    );
    await openReport(t);
    await tap(t, find.text(loc.dating_reportSpam));
    await tap(t, send);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_cardGone), findsOneWidget);
    expect(find.text(loc.dating_reportDangerNoNumber), findsOneWidget);
    expect(find.byKey(const ValueKey('dating_report_call')), findsNothing);
    report.answer = const DatingReportAnswer(ok: true, slaHours: 4);
    await tap(t, send);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportSentTestingNoNumber), findsOneWidget);
  });

  testWidgets('M-6: a pause that fails says so and Pause stays', (t) async {
    final report = FakeDatingReport();
    final shell = await chat(t, report);
    shell.life.result = const DatingLifecycleResult.refused(
      DatingLifecycleError.failed,
    );
    await openReport(t);
    await tap(t, find.text(loc.dating_reportMoney));
    await tap(t, send);
    await t.pumpAndSettle();
    await tap(t, find.byKey(const ValueKey('dating_report_pause')));
    await t.pumpAndSettle();
    expect(shell.life.calls, ['pause']);
    expect(find.text(loc.dating_errorGeneric), findsOneWidget);
    expect(find.text(loc.dating_pausedLine), findsNothing);
    expect(find.byKey(const ValueKey('dating_report_pause')), findsOneWidget);
  });

  testWidgets('M-7: the thanks is one live region, the not-blocked line in '
      'it', (t) async {
    final report =
        FakeDatingReport()
          ..answer = const DatingReportAnswer(ok: true, blocked: false);
    await chat(t, report);
    await openReport(t);
    await tap(t, find.text(loc.dating_reportHarassment));
    await tap(t, send);
    await t.pumpAndSettle();
    final live = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.liveRegion == true,
    );
    expect(live, findsOneWidget);
    expect(
      find.descendant(
        of: live,
        matching: find.text(loc.dating_reportNotBlocked('Kofi')),
      ),
      findsOneWidget,
    );
  });
}
