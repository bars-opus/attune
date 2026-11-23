// Spec 2 W7a Task 4 (§3.1, §3.7, §3.15 Restricted, hold, appeal; §6.3;
// R-43, R-56; D8): the restricted screen at /dating/restricted: the
// category first in the person's own words, each type's copy, Appeal once
// where allowed (sent once under one key; offline it waits), the appeal's
// state, Contact support, the age check's Verify with ID through support;
// the section's restricted, hold and age-check cards lead there and an
// accepted appeal is said on the section; another account starts from
// nothing; goldens at 1.0, 1.3, 2.0 and RTL; the three guidelines; the
// manual says Report again.
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/restricted_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';

final _ends = DateTime.utc(2026, 12, 1, 12);

DatingRestrictionRead _read(
  DatingRestrictionType type, {
  DateTime? ends,
  DatingReportCategory? category = DatingReportCategory.harassment,
  bool canAppeal = false,
  DatingAppeal? appeal,
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

void main() {
  final loc = AppLocalizationsEn();

  test('the restriction read fails closed and names no one', () {
    final r = DatingRestrictionRead.fromJson({
      'ok': true,
      'appeal_accepted': false,
      'restriction': {
        'id': 'r1',
        'type': 'hold',
        'ends_at': null,
        'category': 'threat_to_life',
        'can_appeal': false,
        'appeal': null,
      },
    });
    expect(r.restriction!.type, DatingRestrictionType.hold);
    expect(r.restriction!.category, DatingReportCategory.threatToLife);
    expect(DatingRestrictionRead.fromJson({'ok': false}).ok, isFalse);
    expect(
      DatingRestriction.fromJson({'id': 'x', 'type': 'under_review'}),
      isNull,
    );
    expect(
      DatingAppeal.fromJson({'state': 'rejected'})!.state,
      DatingAppealState.rejected,
    );
    for (final c in DatingReportCategory.values) {
      expect(datingRestrictionLabel(loc, c), isNotEmpty);
      // The person's own plain words, never the reporter's voice.
      expect(datingRestrictionLabel(loc, c), isNot(matches(RegExp(r'\bme\b'))));
      expect(datingRestrictionLabel(loc, c), isNot(startsWith('They')));
    }
    expect(datingRestrictionLabel(loc, null), loc.dating_reasonOther);
  });

  Future<(DatingShell, FakeDatingReport, List<String>)> open(
    WidgetTester t,
    DatingRestrictionRead read, {
    bool online = true,
  }) async {
    final fake = FakeDatingReport()..read = read;
    final contacted = <String>[];
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.restricted,
      online: online,
      overrides: [
        ...datingReportOverrides(fake),
        datingSupportContactProvider.overrideWithValue(
          (context, mail) async => contacted.add('support'),
        ),
      ],
    );
    return (shell, fake, contacted);
  }

  testWidgets('a hold: the category first, the hold\'s words, no Appeal', (
    t,
  ) async {
    // W7 final client fix (I-3): a P0 report's interim hold.
    await open(
      t,
      const DatingRestrictionRead(
        ok: true,
        staffed: true,
        restriction: DatingRestriction(
          id: 'r1',
          type: DatingRestrictionType.hold,
          category: DatingReportCategory.threatToLife,
          source: DatingRestrictionSource.p0Interim,
        ),
      ),
    );
    final about = loc.dating_restrictedAbout(loc.dating_reasonThreatToLife);
    expect(find.text(about), findsOneWidget);
    expect(find.text(loc.dating_restrictedHold), findsOneWidget);
    expect(
      t.getTopLeft(find.text(about)).dy,
      lessThan(t.getTopLeft(find.text(loc.dating_restrictedHold)).dy),
    );
    expect(find.text(loc.dating_appeal), findsNothing);
    expect(find.text(loc.flow_holdContact), findsOneWidget);
  });

  testWidgets('until a date: the reason, the date, what it means, Appeal '
      'once; sent, the screen reads again and says so', (t) async {
    final (shell, fake, _) = await open(
      t,
      _read(DatingRestrictionType.suspended, ends: _ends, canAppeal: true),
    );
    expect(
      find.text(loc.dating_restrictedReason(loc.dating_reasonHarassment)),
      findsOneWidget,
    );
    expect(
      find.text(
        loc.dating_restrictedUntil(MyDateFormat.toDate(_ends.toLocal())),
      ),
      findsOneWidget,
    );
    expect(find.text(loc.dating_restrictedMeans), findsOneWidget);
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_appeal')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('dating_appeal_text')),
      '  I didn\'t do this.  ',
    );
    fake.read = _read(
      DatingRestrictionType.suspended,
      ends: _ends,
      appeal: const DatingAppeal(state: DatingAppealState.open),
    );
    await tapInReach(t, find.byKey(const ValueKey('dating_appeal_send')));
    await t.pumpAndSettle();
    expect(fake.appeals.single.$2, 'r1');
    expect(fake.appeals.single.$3, 'I didn\'t do this.');
    expect(fake.reads, 2);
    expect(find.text(loc.dating_appealSent), findsOneWidget);
    expect(find.text(loc.dating_appeal), findsNothing);
    expect(shell.location, DatingPaths.restricted);
  });

  testWidgets('the appeal waits offline; busy keeps its key', (t) async {
    final (_, fake, _) = await open(
      t,
      _read(DatingRestrictionType.suspended, canAppeal: true),
      online: false,
    );
    expect(find.text(loc.dating_restrictedClosed), findsOneWidget);
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_appeal')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_offline), findsOneWidget);
    await tapInReach(t, find.byKey(const ValueKey('dating_appeal_send')));
    await t.pump();
    expect(fake.appeals, isEmpty);

    final (_, busy, _) = await open(
      t,
      _read(DatingRestrictionType.suspended, canAppeal: true),
    );
    busy.appealAnswer = DatingReportAnswer.busy;
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_appeal')));
    await t.pumpAndSettle();
    await tapInReach(t, find.byKey(const ValueKey('dating_appeal_send')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_busy), findsOneWidget);
    busy.appealAnswer = const DatingReportAnswer(ok: true);
    await tapInReach(t, find.byKey(const ValueKey('dating_appeal_send')));
    await t.pumpAndSettle();
    expect(busy.appeals, hasLength(2));
    expect(busy.appeals[1].$1, busy.appeals[0].$1);
  });

  testWidgets('the age check: its words, Verify with ID through support; '
      'a rejected appeal; nothing left; an accepted appeal', (t) async {
    final (_, _, contacted) = await open(
      t,
      _read(DatingRestrictionType.ageReview, category: null),
    );
    expect(find.text(loc.dating_sectionAgeReview), findsOneWidget);
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_verify')));
    await t.pump();
    expect(contacted, ['support']);
    await open(
      t,
      _read(
        DatingRestrictionType.suspended,
        appeal: const DatingAppeal(state: DatingAppealState.rejected),
      ),
    );
    expect(find.text(loc.dating_appealRejected), findsOneWidget);
    await open(t, DatingRestrictionRead.none);
    expect(find.text(loc.dating_restrictedNone), findsOneWidget);
    await open(t, const DatingRestrictionRead(ok: true, appealAccepted: true));
    // W7 final client fix (I-4, R-53): Dating stays paused until Resume.
    expect(find.text(loc.dating_appealAcceptedPaused), findsOneWidget);
  });

  testWidgets('D8: another account sees nothing of the last one\'s '
      'restriction', (t) async {
    final (shell, fake, _) = await open(
      t,
      _read(DatingRestrictionType.hold, category: DatingReportCategory.csam),
    );
    final about = loc.dating_restrictedAbout(loc.dating_reasonCsam);
    expect(find.text(about), findsOneWidget);
    fake.read = DatingRestrictionRead.none;
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    expect(find.text(about), findsNothing);
    await t.pumpAndSettle();
    expect(find.text(about), findsNothing);
  });

  Future<FlowHarness> section(WidgetTester t, DatingHome state) async {
    await t.pumpWidget(const SizedBox());
    return pumpFlowScreen(
      t,
      () => const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: DatingSection(),
        ),
      ),
      overrides: [
        ...datingShellOverrides(home: FakeDatingHomeGateway(home: state)),
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: 'dating')),
          ),
        ),
      ],
    );
  }

  testWidgets('the section: restricted, hold and the age check lead to the '
      'screen; an accepted appeal is said on the active and paused cards', (
    t,
  ) async {
    for (final s in [
      DatingHomeState.restricted,
      DatingHomeState.hold,
      DatingHomeState.ageReview,
    ]) {
      await section(t, DatingHome(state: s));
      await tapInReach(t, find.text(loc.dating_restrictedSeeWhy));
      await t.pumpAndSettle();
      expect(find.text('at ${DatingPaths.restricted}'), findsOneWidget);
    }
    await section(
      t,
      const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.gates,
        appealAccepted: true,
      ),
    );
    // Fix round 1 (M-6): the paused card's own accepted line.
    expect(find.text(loc.dating_appealAcceptedPaused), findsOneWidget);
    expect(find.text(loc.dating_sectionPaused), findsOneWidget);
    await section(t, const DatingHome(state: DatingHomeState.active));
    expect(find.text(loc.dating_appealAccepted), findsNothing);
    expect(
      DatingHome.fromJson({
        'state': 'active',
        'appeal_accepted': true,
      }).appealAccepted,
      isTrue,
    );
  });

  testWidgets('goldens at 1.0, 1.3, 2.0 and RTL; the three guidelines', (
    t,
  ) async {
    final fake =
        FakeDatingReport()
          ..read = _read(
            DatingRestrictionType.suspended,
            ends: _ends,
            canAppeal: true,
          );
    Widget screen() => const DatingRestrictedScreen();
    final overrides = [
      ...datingShellOverrides(),
      ...datingReportOverrides(fake),
    ];
    await expectFlowGoldens(
      t,
      'dating_restricted',
      screen,
      overrides: overrides,
    );
    await pumpFlowScreen(t, screen, overrides: overrides);
    await expectFlowGuidelines(t);
  });

  testWidgets('the manual says Report again (R-43) and explains reporting '
      'and restrictions', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    String content(String id) =>
        DatingModeDocs()
            .getSections(context)
            .expand((s) => s.contents)
            .firstWhere((c) => c.id == id)
            .content;
    expect(content('dating_money'), contains('report them'));
    expect(content('dating_chat'), contains('lets you report, block'));
    expect(content('dating_report'), contains('appeal once'));
  });
}
