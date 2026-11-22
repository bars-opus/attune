// Spec 2 W7 final client fix (final-client-review.md): the app's items.
// I-1 a P0 card report always takes the card away, whatever "Also block"
// did, and its not-blocked line promises no retry; I-2 Pause Dating on the
// report sheet reads the home and Today again, and says paused only when
// the server does; I-3 the restricted screen's hold line depends on the
// hold's source (the 24-hour interim line only for a P0 report's interim
// hold, never after a rejected appeal); I-4 an accepted appeal says Resume
// unless the home is active (R-53); I-6 the ID check's reference code on
// the screen and in the email's subject, never another account's, and no
// phone number asked for; M-4 the paused card's Contact support says no
// email app in the app's own words; M-5 the report field's label above the
// field, whole at 2.0; M-12 Today's not_eligible leads a held person to
// why; M-13 a send refused as restricted leads to why; M-16 the manual's
// carried-hold wording.
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/core/utils/constants.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
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
import '../support/dating_today_fakes.dart';

Future<void> _tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

/// A FlowTextLink's own button (its key is on the full-width Align).
Finder _button(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextButton),
);

DatingRestrictionRead _read(
  DatingRestrictionType type, {
  DatingRestrictionSource? source,
  String? code,
  DatingAppeal? appeal,
  bool canAppeal = false,
}) => DatingRestrictionRead(
  ok: true,
  restriction: DatingRestriction(
    id: 'r1',
    type: type,
    category: DatingReportCategory.harassment,
    source: source,
    idCheckCode: code,
    appeal: appeal,
    canAppeal: canAppeal,
  ),
);

void main() {
  final loc = AppLocalizationsEn();
  const email = AppConstants.supportEmail;
  final send = find.byKey(const ValueKey('dating_report_send'));

  Future<(DatingShell, FakeDatingToday, FakeDatingReport)> openToday(
    WidgetTester t, {
    DatingReportAnswer? answer,
    FakeDatingHomeGateway? home,
    Map<String, Object?>? json,
  }) async {
    final today = FakeDatingToday(today: json);
    final report = FakeDatingReport();
    if (answer != null) report.answer = answer;
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      home: home,
      overrides: [
        ...datingTodayOverrides(today),
        ...datingReportOverrides(report),
      ],
    );
    return (shell, today, report);
  }

  Future<void> reportCard(WidgetTester t, String category) async {
    await tapInReach(t, find.text(loc.dating_cardMore));
    await t.pumpAndSettle();
    await tapInReach(t, find.text(loc.dating_reportTitle('Kofi')));
    await t.pumpAndSettle();
    await _tap(t, find.text(category));
    await _tap(t, send);
    await t.pumpAndSettle();
  }

  group('I-1: a P0 card report takes the card away', () {
    testWidgets('"Also block" on and the block refused: the card goes, '
        'Today reads again, and the thanks promises no retry', (t) async {
      final (_, today, report) = await openToday(
        t,
        answer: const DatingReportAnswer(ok: true, slaHours: 4, blocked: false),
      );
      expect(find.text(loc.dating_cardMore), findsOneWidget);
      final reads = today.reads;
      await reportCard(t, loc.dating_reportUnderage);
      expect(report.reports.single.alsoBlock, isTrue, reason: 'P0 default');
      expect(find.text(loc.dating_reportNotBlockedEnded('Kofi')), findsOne);
      expect(find.text(loc.dating_reportNotBlocked('Kofi')), findsNothing);
      await _tap(t, find.byKey(const ValueKey('dating_report_close')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_cardMore), findsNothing);
      expect(find.text(loc.dating_blockDone('Kofi')), findsNothing);
      expect(today.reads, greaterThan(reads));
    });

    test('takesCardAway is P0, whatever "Also block" was', () {
      for (final c in DatingReportCategory.values) {
        for (final also in [true, false]) {
          expect(
            DatingReportOutcome(
              blocked: false,
              alsoBlock: also,
              category: c,
            ).takesCardAway,
            c.priority == 0,
            reason: '${c.wire} also=$also',
          );
        }
      }
    });

    testWidgets('a P2 card report whose block was refused still offers the '
        'retry (the card stays)', (t) async {
      await openToday(
        t,
        answer: const DatingReportAnswer(ok: true, slaHours: 48, blocked: false),
      );
      await reportCard(t, loc.dating_reportHarassment);
      expect(find.text(loc.dating_reportNotBlocked('Kofi')), findsOneWidget);
    });
  });

  group('I-2: Pause Dating from the report sheet', () {
    testWidgets('from a card on Today: paused only when the server says so; '
        'the home and Today read again, so Today shows the paused line', (
      t,
    ) async {
      final (shell, today, _) = await openToday(
        t,
        answer: const DatingReportAnswer(ok: true, slaHours: 24),
      );
      final homeReads = <int>[];
      shell.container.listen(
        datingHomeProvider('ama'),
        (_, __) {},
        fireImmediately: true,
      );
      await t.pumpAndSettle();
      homeReads.add(shell.home.reads);
      await reportCard(t, loc.dating_reportMoney);
      expect(find.text(loc.dating_reportScam), findsOneWidget);
      shell.life.result = const DatingLifecycleResult.done('paused');
      today.json = {'ok': false, 'reason': 'paused'};
      await _tap(t, find.byKey(const ValueKey('dating_report_pause')));
      await t.pumpAndSettle();
      expect(shell.life.calls, ['pause']);
      expect(find.text(loc.dating_pausedLine), findsOneWidget);
      expect(shell.home.reads, greaterThan(homeReads.single));
      await _tap(t, find.byKey(const ValueKey('dating_report_close')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_sectionPaused), findsOneWidget);
      expect(find.text(loc.dating_cardMore), findsNothing);
    });

    testWidgets('an ok answer that isn\'t paused claims nothing and offers '
        'Pause no more; a failure keeps Pause', (t) async {
      final (shell, _, _) = await openToday(
        t,
        answer: const DatingReportAnswer(ok: true, slaHours: 24),
      );
      await reportCard(t, loc.dating_reportMoney);
      shell.life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.failed,
      );
      await _tap(t, find.byKey(const ValueKey('dating_report_pause')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
      expect(find.byKey(const ValueKey('dating_report_pause')), findsOne);
      shell.life.result = const DatingLifecycleResult.done('active');
      await _tap(t, find.byKey(const ValueKey('dating_report_pause')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_pausedLine), findsNothing);
      expect(find.text(loc.dating_errorGeneric), findsNothing);
      expect(find.byKey(const ValueKey('dating_report_pause')), findsNothing);
    });
  });

  Future<(DatingShell, FakeDatingReport, List<Uri>)> restricted(
    WidgetTester t,
    DatingRestrictionRead read, {
    FakeDatingHomeGateway? home,
  }) async {
    final fake = FakeDatingReport()..read = read;
    final mails = <Uri>[];
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.restricted,
      home: home,
      overrides: [
        ...datingReportOverrides(fake),
        datingSupportContactProvider.overrideWithValue(
          (context, mail) async => mails.add(mail),
        ),
      ],
    );
    return (shell, fake, mails);
  }

  group('I-3: the hold line by its source', () {
    final holdLine = find.byKey(const ValueKey('dating_restricted_hold_line'));
    String line(WidgetTester t) => t.widget<Text>(
      find.descendant(of: holdLine, matching: find.byType(Text)),
    ).data!;

    testWidgets('a P0 report\'s interim hold: the spec\'s 24-hour line', (
      t,
    ) async {
      await restricted(
        t,
        _read(
          DatingRestrictionType.hold,
          source: DatingRestrictionSource.p0Interim,
        ),
      );
      expect(find.text(loc.flow_slotDatingTitle), findsOneWidget);
      expect(line(t), loc.dating_restrictedHold);
    });

    for (final source in [
      DatingRestrictionSource.moderator,
      DatingRestrictionSource.csam,
      DatingRestrictionSource.carried,
      null,
    ]) {
      testWidgets('a ${source?.wire ?? 'unknown'} hold: no time promise, '
          'never "not a decision yet"', (t) async {
        await restricted(
          t,
          _read(DatingRestrictionType.hold, source: source),
        );
        expect(find.text(loc.flow_slotDatingTitle), findsOneWidget);
        expect(line(t), loc.dating_restrictedHoldPlain);
        expect(find.textContaining('24 hours'), findsNothing);
        expect(find.textContaining("isn't a decision yet"), findsNothing);
      });
    }

    testWidgets('a carried hold whose appeal was rejected never reads "not '
        'a decision yet", even if the server named it interim', (t) async {
      for (final source in [
        DatingRestrictionSource.carried,
        DatingRestrictionSource.p0Interim,
      ]) {
        await restricted(
          t,
          _read(
            DatingRestrictionType.hold,
            source: source,
            appeal: const DatingAppeal(state: DatingAppealState.rejected),
          ),
        );
        expect(find.text(loc.dating_appealRejected), findsOneWidget);
        expect(line(t), loc.dating_restrictedHoldPlain, reason: source.wire);
        expect(find.textContaining("isn't a decision yet"), findsNothing);
      }
    });

    test('the read parses source; an unknown one is null', () {
      DatingRestriction? parse(Object? source) => DatingRestriction.fromJson({
        'id': 'r1',
        'type': 'hold',
        'source': source,
      });
      expect(parse('p0_interim')!.interimHold, isTrue);
      for (final s in ['moderator', 'csam', 'carried', 'nope', null]) {
        expect(parse(s)!.interimHold, isFalse, reason: '$s');
      }
      expect(parse('csam')!.source, DatingRestrictionSource.csam);
      expect(parse('nope')!.source, isNull);
      expect(loc.dating_restrictedHoldPlain, isNot(contains('24')));
    });
  });

  group('I-4: an accepted appeal (R-53)', () {
    testWidgets('paused or not yet read: Resume when you\'re ready', (t) async {
      await restricted(
        t,
        const DatingRestrictionRead(ok: true, appealAccepted: true),
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.paused),
        ),
      );
      expect(find.text(loc.flow_slotDatingTitle), findsOneWidget);
      expect(find.text(loc.dating_appealAcceptedPaused), findsOneWidget);
      expect(find.text(loc.dating_appealAccepted), findsNothing);
    });

    testWidgets('a home that reads active (resumed already): open again', (
      t,
    ) async {
      await restricted(
        t,
        const DatingRestrictionRead(ok: true, appealAccepted: true),
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active),
        ),
      );
      expect(find.text(loc.dating_appealAccepted), findsOneWidget);
      expect(find.text(loc.dating_appealAcceptedPaused), findsNothing);
    });
  });

  group('I-6: the ID check\'s reference code', () {
    final codeLine = find.byKey(const ValueKey('dating_restricted_id_code'));
    final verify = find.byKey(const ValueKey('dating_restricted_verify'));

    testWidgets('shown, selectable and spelt out; in the email\'s subject; '
        'no phone number asked for', (t) async {
      final (_, _, mails) = await restricted(
        t,
        _read(
          DatingRestrictionType.ageReview,
          source: DatingRestrictionSource.idCheck,
          code: 'AB23CD45',
        ),
      );
      expect(find.text(loc.flow_slotDatingTitle), findsOneWidget);
      expect(codeLine, findsOneWidget);
      expect(
        find.descendant(of: codeLine, matching: find.byType(SelectableText)),
        findsOneWidget,
      );
      final handle = t.ensureSemantics();
      expect(
        find.bySemanticsLabel(loc.dating_restrictedIdCode('A B 2 3 C D 4 5')),
        findsOneWidget,
      );
      handle.dispose();
      expect(
        find.text(loc.dating_restrictedVerifyHelp(email)),
        findsOneWidget,
      );
      expect(loc.dating_restrictedVerifyHelp(email), isNot(contains('phone')));
      await tapInReach(t, verify);
      await t.pump();
      expect(
        mails.single.toString(),
        'mailto:$email?subject=${Uri.encodeComponent('Attune ID check: AB23CD45')}',
      );
      expect(mails.single.queryParameters['subject'], isNot(contains('Dating')));
    });

    testWidgets('no code (an age check no case asked for): the help line '
        'alone and the plain subject', (t) async {
      final (_, _, mails) = await restricted(
        t,
        _read(
          DatingRestrictionType.ageReview,
          source: DatingRestrictionSource.ageAssurance,
        ),
      );
      expect(find.text(loc.dating_sectionAgeReview), findsOneWidget);
      expect(codeLine, findsNothing);
      await tapInReach(t, verify);
      await t.pump();
      expect(mails.single.queryParameters['subject'], 'Attune ID check');
    });

    testWidgets('D8: another account never sees the last one\'s code', (
      t,
    ) async {
      final (shell, fake, mails) = await restricted(
        t,
        _read(
          DatingRestrictionType.ageReview,
          source: DatingRestrictionSource.idCheck,
          code: 'AB23CD45',
        ),
      );
      expect(codeLine, findsOneWidget);
      fake.read = _read(
        DatingRestrictionType.ageReview,
        source: DatingRestrictionSource.ageAssurance,
      );
      shell.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      expect(find.text(loc.dating_sectionAgeReview), findsOneWidget);
      expect(find.textContaining('AB23CD45'), findsNothing);
      await tapInReach(t, verify);
      await t.pump();
      expect(mails.single.queryParameters['subject'], 'Attune ID check');
    });

    test('only a well-formed code of an asked age check is kept', () {
      String? code(Map<String, Object?> over) =>
          DatingRestriction.fromJson({
            'id': 'r1',
            'type': 'age_review',
            'source': 'id_check',
            'id_check_code': 'AB23CD45',
            ...over,
          })!.idCheckCode;
      expect(code({}), 'AB23CD45');
      for (final bad in [
        'AB23CD4',
        'AB23CD456',
        'ab23cd45',
        'AB23CD4O',
        'AB23CDI5',
        'AB23CD1L',
        'AB23 D45',
        'AB23CD45\nBcc: x',
        42,
        null,
      ]) {
        expect(code({'id_check_code': bad}), isNull, reason: '$bad');
      }
      expect(code({'source': 'age_assurance'}), isNull);
      expect(code({'type': 'hold'}), isNull);
    });
  });

  testWidgets('M-4 (W4b carry): the paused card\'s Contact support, with no '
      'email app, says so in the app\'s words with the address', (t) async {
    await pumpFlowScreen(
      t,
      () => const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: DatingSection(),
        ),
      ),
      overrides: [
        ...datingShellOverrides(
          home: FakeDatingHomeGateway(
            home: const DatingHome(
              state: DatingHomeState.paused,
              pauseReason: DatingPauseReason.verification,
              check: DatingPauseCheck.ended,
              canResume: false,
              hasData: true,
            ),
          ),
        ),
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: 'dating')),
          ),
        ),
        datingSupportContactProvider.overrideWithValue(
          (context, mail) async => throw StateError('no email app'),
        ),
      ],
    );
    expect(find.byKey(const ValueKey('dating_section_contact')), findsOne);
    await tapInReach(t, _button('dating_section_contact'));
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Cannot open email app'), findsNothing);
    final noMail = find.byKey(const ValueKey('dating_section_no_mail'));
    expect(t.widget<SelectableText>(noMail).data, loc.dating_restrictedNoMail(email));
  });

  testWidgets('final minor 1: the Me card\'s hold line is neutral (no "not a '
      'decision yet": a carried hold may be decided)', (t) async {
    await pumpFlowScreen(
      t,
      () => const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: DatingSection(),
        ),
      ),
      overrides: [
        ...datingShellOverrides(
          home: FakeDatingHomeGateway(
            home: const DatingHome(state: DatingHomeState.hold),
          ),
        ),
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: 'dating')),
          ),
        ),
      ],
    );
    expect(find.byKey(const ValueKey('dating_section_restricted')), findsOne);
    expect(loc.dating_sectionHold, loc.dating_restrictedHoldPlain);
    expect(find.text(loc.dating_sectionHold), findsOneWidget);
    expect(find.textContaining("isn't a decision yet"), findsNothing);
  });

  testWidgets('M-5: at 2.0 the report field\'s label is whole, above the '
      'field, and still names it', (t) async {
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      textScale: 2.0,
      overrides: [
        ...datingChatOverrides(FakeDatingChat()),
        ...datingReportOverrides(FakeDatingReport()),
      ],
    );
    await _tap(t, find.bySemanticsLabel(loc.dating_chatSafetyLabel));
    await t.pumpAndSettle();
    await _tap(t, find.text(loc.dating_reportTitle('Kofi')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_reportWhat), findsWidgets);
    final label = find.text(loc.dating_reportMore);
    await t.ensureVisible(label);
    await t.pumpAndSettle();
    expect(label, findsOneWidget);
    expect(
      find.descendant(of: find.byType(InputDecorator), matching: label),
      findsNothing,
    );
    expect(t.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse);
    final count = find.text(loc.dating_gentleWaitAnswerCount(0, 500));
    expect(count, findsOneWidget);
    expect(
      find.descendant(of: find.byType(InputDecorator), matching: count),
      findsNothing,
    );
    final handle = t.ensureSemantics();
    final node = t.getSemantics(
      find.byKey(const ValueKey('dating_report_details')),
    );
    expect(node.label, contains(loc.dating_reportMore));
    expect(node.hasFlag(SemanticsFlag.isTextField), isTrue);
    handle.dispose();
  });

  group('M-12: Today\'s not_eligible', () {
    for (final state in [
      DatingHomeState.hold,
      DatingHomeState.restricted,
      DatingHomeState.ageReview,
    ]) {
      testWidgets('a ${state.name} home: See why opens the restricted '
          'screen', (t) async {
        await openToday(
          t,
          home: FakeDatingHomeGateway(home: DatingHome(state: state)),
          json: {'ok': false, 'reason': 'not_eligible'},
        );
        expect(find.text(loc.dating_sectionUnavailable), findsOneWidget);
        await _tap(t, _button('dating_today_see_why'));
        await t.pumpAndSettle();
        expect(find.byType(DatingRestrictedScreen), findsOneWidget);
      });
    }

    testWidgets('any other home: no See why', (t) async {
      await openToday(
        t,
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active),
        ),
        json: {'ok': false, 'reason': 'not_eligible'},
      );
      expect(find.text(loc.dating_sectionUnavailable), findsOneWidget);
      expect(find.byKey(const ValueKey('dating_today_see_why')), findsNothing);
    });
  });

  testWidgets('M-13: a send refused as restricted says so and leads to why', (
    t,
  ) async {
    final fake = FakeDatingChat()..refusals['send'] = 'restricted';
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      overrides: datingChatOverrides(fake),
    );
    expect(find.text('Kofi, 31'), findsOneWidget);
    expect(find.byKey(const ValueKey('dating_chat_see_why')), findsNothing);
    await t.enterText(
      find.byKey(const ValueKey('dating_chat_composer')),
      'Hello',
    );
    await _tap(t, find.byKey(const ValueKey('dating_chat_send')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_chatRestricted), findsOneWidget);
    await _tap(t, _button('dating_chat_see_why'));
    await t.pumpAndSettle();
    expect(find.byType(DatingRestrictedScreen), findsOneWidget);
  });

  testWidgets('M-16: the manual says a carried hold can be appealed', (
    t,
  ) async {
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
    expect(
      report,
      contains(
        'A pause while we look into a report has no appeal unless it was '
        'carried over from an earlier account: it ends with a decision.',
      ),
    );
  });
}
