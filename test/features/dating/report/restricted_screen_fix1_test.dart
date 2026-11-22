// Spec 2 W7a Task 4 fix round 1 (task-4-review.md): K-1 a report sheet the
// lock or quick exit closes mid-send (closeDatingSheets) still hands the
// chat its outcome; K-2 (R-53) a hold leaves the chats open: the hold card
// and the hold screen lead to Conversations; M-1 nothing in the appeal
// sheet clips at 2.0 (the label short, "Optional" and the count under the
// field); M-2 the manual says what the server does; M-3 Verify with ID
// says what it does and shows the address, and no mail app is said in the
// app's own words; M-4 the active card's accepted line, a forced close
// mid-send, every category's label, the category first on a dated
// suspension; M-5 the sheet says it is the one appeal; M-6 the paused card
// never says "open again" above "paused", and the accepted screen leads
// back; M-7 the appeal and report sheets open without the slide (§3.15).
import 'dart:async';

import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/dating/chat/conversations_screen.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/restricted_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_fakes.dart';
import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';

DatingRestrictionRead _read(
  DatingRestrictionType type, {
  DatingReportCategory? category = DatingReportCategory.harassment,
  bool canAppeal = false,
  DateTime? ends,
}) => DatingRestrictionRead(
  ok: true,
  restriction: DatingRestriction(
    id: 'r1',
    type: type,
    endsAt: ends,
    category: category,
    canAppeal: canAppeal,
  ),
);

final _appealable = _read(DatingRestrictionType.suspended, canAppeal: true);

const _card = DatingSafetyCard(
  id: 'e1',
  messageId: 'd2',
  family: 'financial_request',
);

void main() {
  final loc = AppLocalizationsEn();
  const email = AppConstants.supportEmail;
  final appealButton = find.byKey(const ValueKey('dating_restricted_appeal'));
  final send = find.byKey(const ValueKey('dating_appeal_send'));

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingReport fake, {
    double textScale = 1.0,
    DatingSupportContact? contact,
  }) => pumpDatingShell(
    t,
    initial: DatingPaths.restricted,
    textScale: textScale,
    overrides: [
      ...datingReportOverrides(fake),
      if (contact != null)
        datingSupportContactProvider.overrideWithValue(contact),
    ],
  );

  Future<void> openSheet(WidgetTester t) async {
    await tapInReach(t, appealButton);
    await t.pumpAndSettle();
    expect(send, findsOneWidget, reason: 'the appeal sheet is open');
  }

  testWidgets('K-1: a report sheet closed from outside (the lock, quick '
      'exit) mid-send still hands the chat its outcome', (t) async {
    final fake = FakeDatingChat()..cardList = const [_card];
    final report = FakeDatingReport()..hold = Completer<void>();
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      overrides: [
        ...datingChatOverrides(fake),
        ...datingReportOverrides(report),
      ],
    );
    await tapInReach(t, find.byKey(const ValueKey('dating_card_report')));
    await t.pumpAndSettle();
    await tapInReach(t, find.text(loc.dating_reportMoney));
    await t.pump();
    await tapInReach(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pump();
    expect(report.reports, hasLength(1));
    closeDatingSheets();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportSend), findsNothing);
    expect(find.byKey(const ValueKey('dating_card_e1')), findsOneWidget);
    report.hold!.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dating_card_e1')), findsNothing);
    expect(fake.dismissed, contains('e1'));
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

  testWidgets('K-2 (R-53): the hold card leads to Conversations; the '
      'restricted and age-check cards do not', (t) async {
    await section(t, const DatingHome(state: DatingHomeState.hold));
    await tapInReach(t, find.text(loc.dating_chatsTitle));
    await t.pumpAndSettle();
    expect(find.text('at ${DatingPaths.chats}'), findsOneWidget);
    for (final s in [DatingHomeState.restricted, DatingHomeState.ageReview]) {
      await section(t, DatingHome(state: s));
      expect(find.text(loc.dating_chatsTitle), findsNothing);
    }
  });

  testWidgets('K-2 (R-53): the hold screen leads to Conversations', (t) async {
    await open(t, FakeDatingReport()..read = _read(DatingRestrictionType.hold));
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_chats')));
    await t.pumpAndSettle();
    // A push keeps the router's base location; the page is what counts.
    expect(find.byType(DatingConversationsScreen), findsOneWidget);
    await open(t, FakeDatingReport()..read = _appealable);
    expect(find.text(loc.dating_chatsTitle), findsNothing);
  });

  testWidgets('M-1/M-5: at 2.0 the appeal sheet says it is the one appeal, '
      'and its label and "Optional" count are whole, outside the field', (
    t,
  ) async {
    await open(t, FakeDatingReport()..read = _appealable, textScale: 2.0);
    await openSheet(t);
    expect(find.text(loc.dating_appealOnce), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('dating_appeal_text')), 'Hi');
    await t.pump();
    final count = find.text(loc.dating_appealCount(2, 500));
    expect(count, findsOneWidget);
    expect(
      find.descendant(of: find.byType(InputDecorator), matching: count),
      findsNothing,
    );
    for (final text in [
      count,
      find.text(loc.dating_appealOnce),
      find.text(loc.dating_appealHint),
    ]) {
      expect(
        t.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isFalse,
        reason: '$text',
      );
    }
    expect(loc.dating_appealHint, 'Tell us what happened');
    // The field is still named by the label for a screen reader.
    final handle = t.ensureSemantics();
    final node = t.getSemantics(
      find.byKey(const ValueKey('dating_appeal_text')),
    );
    expect(node.label, contains(loc.dating_appealHint));
    expect(node.hasFlag(SemanticsFlag.isTextField), isTrue);
    handle.dispose();
    expect(t.takeException(), isNull);
  });

  testWidgets('M-2: the manual says what the server does', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    final report =
        DatingModeDocs()
            .getSections(context)
            .expand((s) => s.contents)
            .firstWhere((c) => c.id == 'dating_report')
            .content;
    expect(report, contains('A person reviews every report.'));
    expect(report, contains('only when separate reports'));
    expect(report, isNot(contains('confirmed')));
    expect(report, isNot(contains('in a word or two')));
    expect(
      report,
      contains(
        'If your Dating account is suspended, you can '
        'appeal once',
      ),
    );
    expect(report, contains('no appeal'));
  });

  testWidgets('M-3: Verify with ID says what it does and shows the address; '
      'no mail app is said in the app\'s words, with the address', (t) async {
    await open(
      t,
      FakeDatingReport()
        ..read = _read(DatingRestrictionType.ageReview, category: null),
      contact: (context, mail) async => throw StateError('no mail app'),
    );
    expect(find.text(loc.dating_restrictedVerifyHelp(email)), findsOneWidget);
    expect(find.text(loc.dating_restrictedNoMail(email)), findsNothing);
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_verify')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_restrictedNoMail(email)), findsOneWidget);
    expect(find.textContaining('Cannot open'), findsNothing);

    await open(
      t,
      FakeDatingReport()..read = _read(DatingRestrictionType.hold),
      contact: (context, mail) async => throw StateError('no mail app'),
    );
    await tapInReach(
      t,
      find.byKey(const ValueKey('dating_restricted_support')),
    );
    await t.pumpAndSettle();
    expect(find.text(loc.dating_restrictedNoMail(email)), findsOneWidget);
  });

  testWidgets('M-4: the active card says an accepted appeal', (t) async {
    await section(
      t,
      const DatingHome(state: DatingHomeState.active, appealAccepted: true),
    );
    expect(find.text(loc.dating_appealAccepted), findsOneWidget);
    expect(find.text(loc.dating_sectionActive), findsOneWidget);
  });

  testWidgets('M-4 (D8): another account mid-send closes the sheet and '
      'leaves no barrier over the next account\'s screen', (t) async {
    final fake =
        FakeDatingReport()
          ..read = _appealable
          ..hold = Completer<void>();
    final shell = await open(t, fake);
    await openSheet(t);
    await tapInReach(t, send);
    await t.pump();
    expect(fake.appeals, hasLength(1));
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pumpAndSettle();
    expect(send, findsNothing);
    expect(find.byType(ModalBarrier), findsOneWidget, reason: 'the page only');
    // The next account's screen takes taps: its own appeal opens.
    await openSheet(t);
    fake.hold!.complete();
    await t.pumpAndSettle();
    expect(send, findsOneWidget, reason: 'the old answer closes nothing');
  });

  test('M-4: every category\'s label, row by row', () {
    const want = {
      DatingReportCategory.underageRisk: 'Concerns about age',
      DatingReportCategory.csam: 'Sexual content involving a child',
      DatingReportCategory.childSafety: 'The safety of children',
      DatingReportCategory.threatToLife:
          'Threatening to kill or seriously hurt someone',
      DatingReportCategory.sextortion: 'Threatening to share someone\'s images',
      DatingReportCategory.romanceScam: 'Asking for money',
      DatingReportCategory.threats: 'Threatening someone',
      DatingReportCategory.entrapment: 'A profile set up to trap people',
      DatingReportCategory.harassment: 'Harassment',
      DatingReportCategory.explicitContent:
          'Sexual messages someone didn\'t want',
      DatingReportCategory.impersonation:
          'Using someone else\'s photos or identity',
      DatingReportCategory.hidingRelationship:
          'Being married or in a relationship',
      DatingReportCategory.spam: 'Spam or selling',
      DatingReportCategory.other: 'Breaking Dating\'s rules',
    };
    expect(want.keys.toSet(), DatingReportCategory.values.toSet());
    for (final e in want.entries) {
      expect(datingRestrictionLabel(loc, e.key), e.value, reason: '${e.key}');
    }
  });

  testWidgets('M-4: a dated suspension says the reason first', (t) async {
    final ends = DateTime.utc(2026, 12, 1, 12);
    await open(
      t,
      FakeDatingReport()
        ..read = _read(DatingRestrictionType.suspended, ends: ends),
    );
    final reason = find.text(
      loc.dating_restrictedReason(loc.dating_reasonHarassment),
    );
    final until = find.text(
      loc.dating_restrictedUntil(MyDateFormat.toDate(ends.toLocal())),
    );
    expect(t.getTopLeft(reason).dy, lessThan(t.getTopLeft(until).dy));
  });

  testWidgets('M-6: the paused card says the accepted appeal without "open '
      'again", above the pause; the accepted screen leads back to Me', (
    t,
  ) async {
    await section(
      t,
      const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.gates,
        appealAccepted: true,
      ),
    );
    final accepted = find.text(loc.dating_appealAcceptedPaused);
    expect(accepted, findsOneWidget);
    expect(find.text(loc.dating_appealAccepted), findsNothing);
    expect(
      t.getTopLeft(accepted).dy,
      lessThan(t.getTopLeft(find.text(loc.dating_sectionPaused)).dy),
    );

    final shell = await open(
      t,
      FakeDatingReport()
        ..read = const DatingRestrictionRead(ok: true, appealAccepted: true),
    );
    await tapInReach(t, find.text(loc.dating_done));
    await t.pumpAndSettle();
    expect(shell.location, startsWith('/home'));
  });

  testWidgets('M-7 (§3.15): the appeal sheet opens without the slide', (
    t,
  ) async {
    await open(t, FakeDatingReport()..read = _appealable);
    await tapInReach(t, appealButton);
    await t.pump();
    final first = t.getTopLeft(send);
    await t.pumpAndSettle();
    expect(t.getTopLeft(send), first);
  });

  testWidgets('M-7 (§3.15): the report sheet opens without the slide', (
    t,
  ) async {
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      overrides: [
        ...datingChatOverrides(FakeDatingChat()..cardList = const [_card]),
        ...datingReportOverrides(FakeDatingReport()),
      ],
    );
    await tapInReach(t, find.byKey(const ValueKey('dating_card_report')));
    await t.pump();
    final title = find.text(loc.dating_reportWhat);
    final first = t.getTopLeft(title);
    await t.pumpAndSettle();
    expect(t.getTopLeft(title), first);
  });
}
