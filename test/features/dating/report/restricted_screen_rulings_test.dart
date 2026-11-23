// Spec 2 W7a Task 4 rulings (task-4-report.md): what the live server and
// the W6/W7 lessons changed in the brief's restricted screen and appeal.
// R-T4-1 a busy read is a calm line and a retry, never red; a failed read
// offline says offline. R-T4-2 the shown set: the loading line and an
// appeal's state read on opening never announce; the appeal just sent is
// the one live line. R-T4-3 the appeal counts code points as the server
// does (DatingRuneLimit). R-T4-4 an appeal on its way survives the sheet:
// back and the barrier do nothing, a pop from outside (the lock, quick
// exit) still re-reads the screen once the answer lands, and a sheet
// opened again after busy sends the same request. R-T4-5 already_appealed
// closes and reads again; appeal_unavailable says so and Close reads
// again. R-T4-6 D8: the appeal sheet closes on another account and sends
// nothing. R-T4-7 (R-54) nothing here waits on the phone check. R-T4-8
// (R-56) the age check has one way to support. R-T4-9 a carried rejected
// appeal: the category first, the decision stands, no Appeal. R-T4-10
// (Task 3 N-1) the no-time sent line is true in testing too.
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/restricted_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';

/// The fake with a read that can be held (the loading state).
class _SlowRead extends FakeDatingReport {
  Completer<void>? gate;

  @override
  Future<DatingRestrictionRead> restriction() async {
    final g = gate;
    if (g != null) await g.future;
    return super.restriction();
  }
}

DatingRestrictionRead _read(
  DatingRestrictionType type, {
  DatingReportCategory? category = DatingReportCategory.harassment,
  bool canAppeal = false,
  DatingAppeal? appeal,
  DateTime? ends,
}) => DatingRestrictionRead(
  ok: true,
  // Spec 2 W8b fix round 1 (M-2): a person reviews (W7's lines).
  staffed: true,
  restriction: DatingRestriction(
    id: 'r1',
    type: type,
    endsAt: ends,
    category: category,
    canAppeal: canAppeal,
    appeal: appeal,
  ),
);

final _appealable = _read(DatingRestrictionType.suspended, canAppeal: true);

int _liveRegions(WidgetTester t) =>
    find
        .byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        )
        .evaluate()
        .length;

void main() {
  final loc = AppLocalizationsEn();
  final appealButton = find.byKey(const ValueKey('dating_restricted_appeal'));
  final send = find.byKey(const ValueKey('dating_appeal_send'));
  final field = find.byKey(const ValueKey('dating_appeal_text'));

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingReport fake, {
    bool online = true,
    bool deviceReady = true,
  }) => pumpDatingShell(
    t,
    initial: DatingPaths.restricted,
    online: online,
    deviceReady: deviceReady,
    overrides: datingReportOverrides(fake),
  );

  Future<void> openSheet(WidgetTester t) async {
    await tapInReach(t, appealButton);
    await t.pumpAndSettle();
    expect(send, findsOneWidget, reason: 'the appeal sheet is open');
  }

  testWidgets('R-T4-1: a busy read is a calm line and Retry reads again', (
    t,
  ) async {
    final fake = FakeDatingReport()..read = DatingRestrictionRead.busy;
    await open(t, fake);
    expect(find.text(loc.dating_busy), findsOneWidget);
    expect(find.text(loc.dating_errorGeneric), findsNothing);
    fake.read = _appealable;
    await tapInReach(t, find.text(loc.dating_retry));
    await t.pumpAndSettle();
    expect(fake.reads, 2);
    expect(appealButton, findsOneWidget);
  });

  testWidgets('R-T4-1: a failed read says offline when offline, else the '
      'error line', (t) async {
    final fake = FakeDatingReport()..read = DatingRestrictionRead.failed;
    await open(t, fake, online: false);
    expect(find.text(loc.dating_offline), findsOneWidget);
    expect(find.text(loc.dating_errorGeneric), findsNothing);
    await open(t, FakeDatingReport()..read = DatingRestrictionRead.failed);
    expect(find.text(loc.dating_errorGeneric), findsOneWidget);
    expect(find.text(loc.dating_retry), findsOneWidget);
  });

  testWidgets('R-T4-2: the loading line and the appeal state read on '
      'opening never announce; the appeal just sent is one live line', (
    t,
  ) async {
    final slow = _SlowRead()..gate = Completer<void>();
    slow.read = _read(
      DatingRestrictionType.suspended,
      appeal: const DatingAppeal(state: DatingAppealState.rejected),
    );
    await pumpDatingShell(
      t,
      initial: DatingPaths.restricted,
      overrides: datingReportOverrides(slow),
    );
    expect(find.text(loc.dating_restrictedLoading), findsOneWidget);
    expect(_liveRegions(t), 0, reason: 'loading');
    slow.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_appealRejected), findsOneWidget);
    expect(_liveRegions(t), 0, reason: 'a rejected appeal read on opening');

    final open_ =
        FakeDatingReport()
          ..read = _read(
            DatingRestrictionType.suspended,
            appeal: const DatingAppeal(state: DatingAppealState.open),
          );
    await open(t, open_);
    expect(find.text(loc.dating_appealSent), findsOneWidget);
    expect(_liveRegions(t), 0, reason: 'an open appeal read on opening');

    final fake = FakeDatingReport()..read = _appealable;
    await open(t, fake);
    await openSheet(t);
    fake.read = _read(
      DatingRestrictionType.suspended,
      appeal: const DatingAppeal(state: DatingAppealState.open),
    );
    await tapInReach(t, send);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_appealSent), findsOneWidget);
    expect(_liveRegions(t), 1, reason: 'the appeal just sent');
  });

  testWidgets('R-T4-3: the appeal counts code points (emoji are two), as '
      'the server does', (t) async {
    final fake = FakeDatingReport()..read = _appealable;
    await open(t, fake);
    await openSheet(t);
    await t.enterText(field, '${'a' * 499}\u{1F44D}\u{1F3FD}\u{1F44D}');
    await t.pump();
    final text = t.widget<TextField>(field).controller!.text;
    expect(text.runes.length, 500);
    expect(find.text(loc.dating_appealCount(500, 500)), findsOne);
    await tapInReach(t, send);
    await t.pumpAndSettle();
    expect(fake.appeals.single.$3!.runes.length, lessThanOrEqualTo(500));
  });

  testWidgets('R-T4-4: back and the barrier do nothing while the appeal is '
      'on its way; the answer closes it and the screen reads again', (t) async {
    final fake =
        FakeDatingReport()
          ..read = _appealable
          ..hold = Completer<void>();
    await open(t, fake);
    t.view.physicalSize = const Size(390, 2600);
    await t.pumpAndSettle();
    await openSheet(t);
    await tapInReach(t, send);
    await t.pump(const Duration(milliseconds: 200));
    expect(fake.appeals, hasLength(1));
    expect(t.widget<TextField>(field).enabled, isFalse);
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 400));
    expect(send, findsOneWidget, reason: 'back');
    await t.tapAt(const Offset(195, 20));
    await t.pump(const Duration(milliseconds: 400));
    expect(send, findsOneWidget, reason: 'the barrier');
    await t.tap(send, warnIfMissed: false);
    await t.pump();
    expect(fake.appeals, hasLength(1), reason: 'one appeal on its way');
    fake.read = _read(
      DatingRestrictionType.suspended,
      appeal: const DatingAppeal(state: DatingAppealState.open),
    );
    fake.hold!.complete();
    await t.pumpAndSettle();
    expect(send, findsNothing);
    expect(fake.reads, 2);
    expect(find.text(loc.dating_appealSent), findsOneWidget);
  });

  testWidgets('R-T4-4: closed from outside (the lock, quick exit) while it '
      'is on its way, the screen still reads again once it lands', (t) async {
    final fake =
        FakeDatingReport()
          ..read = _appealable
          ..hold = Completer<void>();
    await open(t, fake);
    await openSheet(t);
    await tapInReach(t, send);
    await t.pump();
    closeDatingSheets();
    await t.pumpAndSettle();
    expect(send, findsNothing);
    expect(fake.reads, 1);
    fake.read = _read(
      DatingRestrictionType.suspended,
      appeal: const DatingAppeal(state: DatingAppealState.open),
    );
    fake.hold!.complete();
    await t.pumpAndSettle();
    expect(fake.reads, 2);
    expect(find.text(loc.dating_appealSent), findsOneWidget);
  });

  testWidgets('R-T4-4: a sheet opened again after busy sends the same '
      'request', (t) async {
    final fake =
        FakeDatingReport()
          ..read = _appealable
          ..appealAnswer = DatingReportAnswer.busy;
    await open(t, fake);
    await openSheet(t);
    await tapInReach(t, send);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_busy), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(send, findsNothing);
    await openSheet(t);
    fake.appealAnswer = const DatingReportAnswer(ok: true);
    await tapInReach(t, send);
    await t.pumpAndSettle();
    expect(fake.appeals, hasLength(2));
    expect(fake.appeals[1].$1, fake.appeals[0].$1);
  });

  testWidgets('R-T4-5: already_appealed closes and reads again; '
      'appeal_unavailable says so and Close reads again', (t) async {
    final fake =
        FakeDatingReport()
          ..read = _appealable
          ..appealAnswer = const DatingReportAnswer(
            ok: false,
            reason: 'already_appealed',
          );
    await open(t, fake);
    await openSheet(t);
    fake.read = _read(
      DatingRestrictionType.suspended,
      appeal: const DatingAppeal(state: DatingAppealState.rejected),
    );
    await tapInReach(t, send);
    await t.pumpAndSettle();
    expect(send, findsNothing);
    expect(fake.reads, 2);
    expect(find.text(loc.dating_appealRejected), findsOneWidget);
    expect(appealButton, findsNothing);

    final gone =
        FakeDatingReport()
          ..read = _appealable
          ..appealAnswer = const DatingReportAnswer(
            ok: false,
            reason: 'appeal_unavailable',
          );
    await open(t, gone);
    await openSheet(t);
    await tapInReach(t, send);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_cardGone), findsOneWidget);
    gone.read = DatingRestrictionRead.none;
    await tapInReach(t, find.text(loc.dating_close));
    await t.pumpAndSettle();
    expect(gone.reads, 2);
    expect(find.text(loc.dating_restrictedNone), findsOneWidget);
  });

  testWidgets('R-T4-6 (D8): another account closes the appeal sheet and '
      'sends nothing', (t) async {
    final fake = FakeDatingReport()..read = _appealable;
    final shell = await open(t, fake);
    await openSheet(t);
    await t.enterText(field, 'Not me');
    fake.read = DatingRestrictionRead.none;
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    expect(find.text('Not me'), findsNothing);
    await t.pumpAndSettle();
    expect(send, findsNothing);
    expect(find.text(loc.dating_appeal), findsNothing);
    expect(fake.appeals, isEmpty);
    expect(find.text(loc.dating_restrictedNone), findsOneWidget);
  });

  testWidgets('R-T4-7 (R-54): with no phone check the read and the appeal '
      'still go', (t) async {
    final fake = FakeDatingReport()..read = _appealable;
    await open(t, fake, deviceReady: false);
    await openSheet(t);
    await tapInReach(t, send);
    await t.pumpAndSettle();
    expect(fake.appeals, hasLength(1));
  });

  testWidgets('R-T4-8 (R-56): the age check offers one way to support, '
      'Verify with ID', (t) async {
    await open(
      t,
      FakeDatingReport()
        ..read = _read(DatingRestrictionType.ageReview, category: null),
    );
    expect(find.text(loc.dating_restrictedVerifyId), findsOneWidget);
    expect(find.text(loc.flow_holdContact), findsNothing);
    expect(find.textContaining('Reason:'), findsNothing);
    expect(find.textContaining('About:'), findsNothing);
  });

  testWidgets('R-T4-9: a carried rejected appeal: the category first, the '
      'decision stands, no Appeal, Contact support', (t) async {
    await open(
      t,
      FakeDatingReport()
        ..read = _read(
          DatingRestrictionType.suspended,
          category: DatingReportCategory.romanceScam,
          appeal: const DatingAppeal(state: DatingAppealState.rejected),
        ),
    );
    final reason = find.text(
      loc.dating_restrictedReason(loc.dating_reasonMoney),
    );
    expect(reason, findsOneWidget);
    expect(find.text(loc.dating_restrictedClosed), findsOneWidget);
    expect(
      t.getTopLeft(reason).dy,
      lessThan(t.getTopLeft(find.text(loc.dating_appealRejected)).dy),
    );
    expect(appealButton, findsNothing);
    expect(find.text(loc.flow_holdContact), findsOneWidget);
  });

  test(
    'R-T4-10 (Task 3 N-1): the no-time sent line is true in testing too',
    () {
      for (final line in [
        loc.dating_reportSentNoTime('112'),
        loc.dating_reportSentNoTimeNoNumber,
      ]) {
        expect(line, isNot(contains('A person reviews')));
        expect(line, startsWith('Your report is in the review queue.'));
      }
    },
  );

  testWidgets('dark at 2.0: the hold, and the appeal sheet with a refusal in '
      'the theme\'s error red (goldens); the three guidelines', (t) async {
    Widget dark() =>
        Theme(data: AppTheme.darkTheme, child: const DatingRestrictedScreen());
    final hold =
        FakeDatingReport()
          // W7 final client fix (I-3): the spec's interim line is a P0
          // report's interim hold's.
          ..read = const DatingRestrictionRead(
            ok: true,
            staffed: true,
            restriction: DatingRestriction(
              id: 'r1',
              type: DatingRestrictionType.hold,
              category: DatingReportCategory.sextortion,
              source: DatingRestrictionSource.p0Interim,
            ),
          );
    await pumpFlowScreen(
      t,
      dark,
      textScale: 2.0,
      size: const Size(390, 1600),
      overrides: [...datingShellOverrides(), ...datingReportOverrides(hold)],
    );
    expect(find.text(loc.dating_restrictedHold), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dating_restricted.dark_hold_scale2.0.png'),
    );
    await expectFlowGuidelines(t);

    // A fresh ProviderScope (pumpWidget would reuse the last one).
    await t.pumpWidget(const SizedBox());
    final fake =
        FakeDatingReport()
          ..read = _appealable
          ..appealAnswer = const DatingReportAnswer(
            ok: false,
            reason: 'invalid',
          );
    await pumpFlowScreen(
      t,
      dark,
      textScale: 2.0,
      size: const Size(390, 2000),
      overrides: [...datingShellOverrides(), ...datingReportOverrides(fake)],
    );
    await openSheet(t);
    await t.enterText(field, 'I was not there.');
    await tapInReach(t, send);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_errorGeneric), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dating_appeal_sheet.dark_error_scale2.0.png'),
    );
    await expectFlowGuidelines(t);
  });
}
