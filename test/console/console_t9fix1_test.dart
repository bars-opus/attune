// Spec 2 W7c Task 9, fix round 1 (task-9-review.md):
// - I-1: no confirm or result line promises the person is free: every case
//   decision that ends holds says a CSAM hold stays (only the safety
//   owner's CSAM lift ends one), and Dismiss says so after it is done;
// - I-2: the owner opens a case-placed CSAM hold's case from the list;
// - M-1 to M-7: the received time, its range, the consent kind, the
//   escalation kind as a pick, the CSAM copy, the copied key;
// - the owner's Ask for ID → awaiting_id: the case stays in the queue as
//   "Waiting for ID" and offers Lift hold (an adult), Confirm a minor and
//   Dismiss; a decided case lifts nothing (M-8).
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:attune/console/screens/case_screen.dart';
import 'package:attune/console/screens/console_lists.dart';
import 'package:attune/console/screens/law_enforcement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_fakes.dart';

const _owners = "only the safety owner's CSAM lift";

ConsoleAnswer _caseIn(String state, {String kind = 'report'}) => ConsoleAnswer(
  ok: true,
  data: {
    ...consoleCase.data,
    'case': {
      ...(consoleCase.data['case'] as Map),
      'state': state,
      'kind': kind,
    },
  },
);

ConsoleAnswer _queueWith(Map<String, Object?> row) => ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'cases': [row],
  },
);

/// An Auth whose TOTP check passes without moving the session on.
class _StayAuth extends FakeConsoleAuth {
  _StayAuth() : super(ConsoleSession.needsEnrol);

  @override
  Future<bool> verifyTotp(String code, {String? factorId}) async => true;
}

Future<void> _openCase(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('console_case_c1')));
  await t.pumpAndSettle();
}

void main() {
  group('I-1: no copy assumes one hold per person', () {
    test('every confirm that ends holds says what stays', () {
      // W7 final client fix (server round 3): an ID check's actions end no
      // hold (they say nothing here changes the case it came from), and an
      // open case's holds lift with Lift the case's holds.
      for (final copy in [
        kConfirmLiftCaseHolds,
        kConfirmDismiss,
        kConfirmCaseAskForId,
        kConfirmAccept,
      ]) {
        expect(copy, contains(_owners), reason: copy);
        if (copy != kConfirmCaseAskForId) {
          expect(copy, contains('unless another hold or restriction applies'));
        }
        for (final promise in [
          'so this person is back',
          'so the person is back',
          'Dating opens again for this person.',
        ]) {
          expect(copy, isNot(contains(promise)), reason: copy);
        }
      }
      expect(kConfirmAccept, contains('ends this restriction'));
    });

    test('Dismiss says what it did and what stays; never a bare Done.', () {
      final line = consoleActionLine('dismiss', const ConsoleAnswer(ok: true));
      expect(line.text, isNot('Done.'));
      expect(line.text, endsWith(kConsoleOtherHolds));
      final accepted = consoleActionLine(
        'decide_appeal',
        const ConsoleAnswer(ok: true),
        accepted: true,
      );
      expect(accepted.text, endsWith(kConsoleOtherHolds));
    });

    testWidgets('a dismissed case says the other holds stay', (t) async {
      await pumpHome(t);
      await _openCase(t);
      await t.tap(find.byKey(const ValueKey('console_dismiss')));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(find.text('Dismissed. $kConsoleOtherHolds'), findsOneWidget);
    });
  });

  group('I-2: a case-placed CSAM hold opens its case for the owner', () {
    testWidgets('Open its case reads that case; a hash hold has none', (
      t,
    ) async {
      final api = await pumpHome(
        t,
        me: consoleOwner,
        answers: {
          'csam_holds': const ConsoleAnswer(
            ok: true,
            data: {
              'ok': true,
              'holds': [
                {
                  'id': 'h1',
                  'since': '2026-11-20T10:00:00Z',
                  'carried': false,
                  'case_id': null,
                  'escalations': [],
                },
                {
                  'id': 'h2',
                  'since': '2026-11-21T10:00:00Z',
                  'carried': false,
                  'case_id': 'c9',
                  'escalations': [],
                },
              ],
            },
          ),
        },
      );
      await t.tap(find.text('CSAM holds'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console_csam_case_h1')), findsNothing);
      await t.tap(find.byKey(const ValueKey('console_csam_case_h2')));
      await t.pumpAndSettle();
      expect(api.of('case').last, {'case_id': 'c9'});
      expect(find.text('"She said she is in SHS."'), findsOneWidget);
    });

    test('M-6: the CSAM copy never assumes a hash match', () {
      expect(kConfirmCsamLift, contains("hold's grounds were wrong"));
      expect(kConsoleCsamGuidance, contains("hold's grounds were wrong"));
    });
  });

  group('the law-enforcement log (M-1 to M-3)', () {
    Future<FakeConsoleApi> open(WidgetTester t) async {
      final api = await pumpHome(t, me: consoleOwner);
      await t.tap(find.text('Law enforcement'));
      await t.pumpAndSettle();
      return api;
    }

    Future<void> fill(WidgetTester t, {String scope = 'One account'}) async {
      await t.enterText(
        find.byKey(const ValueKey('console_le_jurisdiction')),
        'GH',
      );
      await t.enterText(
        find.byKey(const ValueKey('console_le_basis')),
        'Court order',
      );
      await t.enterText(find.byKey(const ValueKey('console_le_scope')), scope);
    }

    Future<String> record(WidgetTester t, FakeConsoleApi api) async {
      await t.tap(find.byKey(const ValueKey('console_le_record')));
      await t.pumpAndSettle();
      return (api.of('le_record').last['values']!
              as Map<String, Object?>)['received_at']!
          as String;
    }

    String day(DateTime d) => d.toIso8601String().substring(0, 10);

    testWidgets('M-1: a typed day keeps a time of its own, so two requests '
        'on one day are two', (t) async {
      final api = await open(t);
      final today = day(DateTime.now().toUtc());
      Future<String> onDay() async {
        await fill(t);
        await t.enterText(
          find.byKey(const ValueKey('console_le_received')),
          today,
        );
        return record(t, api);
      }

      final first = await onDay();
      await t.pump(const Duration(milliseconds: 5));
      final second = await onDay();
      expect(first, startsWith('${today}T'));
      expect(second, startsWith('${today}T'));
      expect(second, isNot(first));
    });

    testWidgets('M-2: a changed request after a failure takes a new time; '
        'the same one keeps its own', (t) async {
      final api = await open(t);
      api.answers['le_record'] = ConsoleAnswer.busy;
      await fill(t);
      final first = await record(t, api);
      final retry = await record(t, api);
      expect(retry, first);
      await t.pump(const Duration(milliseconds: 5));
      await fill(t, scope: 'Two accounts');
      final changed = await record(t, api);
      expect(changed, isNot(first));
    });

    testWidgets('M-3: a received day outside the log\'s range sends nothing '
        'and says why', (t) async {
      final api = await open(t);
      for (final d in [
        DateTime.now().toUtc().subtract(const Duration(days: 800)),
        DateTime.now().toUtc().add(const Duration(days: 3)),
      ]) {
        await fill(t);
        await t.enterText(
          find.byKey(const ValueKey('console_le_received')),
          day(d),
        );
        await t.tap(find.byKey(const ValueKey('console_le_record')));
        await t.pumpAndSettle();
        expect(find.text(kConsoleReceivedRange), findsOneWidget);
      }
      expect(api.of('le_record'), isEmpty);
    });
  });

  group('the escalation (M-4, M-5)', () {
    testWidgets('the kind is a pick, never a guess; the consent kind says it '
        'needs the person\'s agreement', (t) async {
      final api = await pumpHome(t);
      await _openCase(t);
      await t.ensureVisible(find.byKey(const ValueKey('console_escalate')));
      await t.tap(find.byKey(const ValueKey('console_escalate')));
      await t.pumpAndSettle();
      final save = find.byKey(const ValueKey('console_escalation_save'));
      expect(t.widget<FilledButton>(save).onPressed, isNull);
      expect(find.text(kConsoleConsentOnly), findsNothing);
      await t.tap(find.byKey(const ValueKey('console_escalation_kind')));
      await t.pumpAndSettle();
      await t.tap(find.text("CSA 292, with the person's consent").last);
      await t.pumpAndSettle();
      expect(find.text(kConsoleConsentOnly), findsOneWidget);
      expect(t.widget<FilledButton>(save).onPressed, isNotNull);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(api.of('escalate').single['kind'], 'csa_292_with_consent');
    });

    test('consent_kind_required names a report or a signal, and consent', () {
      final line = consoleReason('consent_kind_required');
      expect(line, contains('report or signal'));
      expect(line, contains('only if the person agreed'));
    });
  });

  group('M-7: the copied key', () {
    testWidgets('a refusal to empty the clipboard is tried again; once '
        'emptied, the key is forgotten', (t) async {
      var writes = 0;
      var refuse = true;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            writes++;
            final text = (call.arguments as Map)['text'] as String;
            if (text.isEmpty && refuse) {
              throw PlatformException(code: 'not_focused');
            }
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final auth = FakeConsoleAuth(ConsoleSession.needsEnrol);
      await t.pumpWidget(
        ConsoleApp(
          api: FakeConsoleApi({'whoami': consoleMe, 'queue': consoleQueue}),
          auth: auth,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_enrol')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_copy_key')));
      await t.pumpAndSettle();
      expect(writes, 1);
      await t.enterText(find.byKey(const ValueKey('console_totp')), '654321');
      await t.tap(find.byKey(const ValueKey('console_verify')));
      await t.pumpAndSettle();
      expect(find.text('Moderator'), findsOneWidget);
      expect(writes, 2, reason: 'one refused empty write');
      refuse = false;
      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      expect(writes, 3, reason: 'the key is kept until a write succeeds');
      await t.enterText(
        find.byKey(const ValueKey('console_phone')),
        '+233244000000',
      );
      await t.tap(find.byKey(const ValueKey('console_next')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('console_code')), '123456');
      await t.tap(find.byKey(const ValueKey('console_next')));
      await t.pumpAndSettle();
      expect(writes, 3, reason: 'emptied once, then forgotten');
    });

    testWidgets('a refresh away from enrolment hides Key copied.', (t) async {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final auth = _StayAuth();
      await t.pumpWidget(
        ConsoleApp(api: FakeConsoleApi({'whoami': consoleMe}), auth: auth),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_enrol')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_copy_key')));
      await t.pumpAndSettle();
      expect(find.text('Key copied.'), findsOneWidget);
      auth.state = ConsoleSession.unreachable;
      await t.enterText(find.byKey(const ValueKey('console_totp')), '000000');
      await t.tap(find.byKey(const ValueKey('console_verify')));
      await t.pumpAndSettle();
      expect(
        find.text("Can't reach the server to check your sign-in."),
        findsOneWidget,
      );
      auth.state = ConsoleSession.needsEnrol;
      await t.tap(find.byKey(const ValueKey('console_retry')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console_copy_key')), findsOneWidget);
      expect(find.text('Key copied.'), findsNothing);
      expect(find.text(kConsoleClipboardHint), findsNothing);
    });
  });

  group('Ask for ID waits for the ID (owner)', () {
    testWidgets('the queue shows a case waiting for ID as such', (t) async {
      await pumpHome(
        t,
        answers: {
          // W7 final client fix (server round 3): the ID check is its own
          // case, listed in the queue's ID section.
          'queue': _queueWith({
            'id': 'c1',
            'kind': 'id_check',
            'priority': 'P1',
            'category': 'underage_risk',
            'state': 'awaiting_id',
            'reports': 1,
            'sla_due_at':
                DateTime.now().add(const Duration(hours: 5)).toIso8601String(),
          }),
        },
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('console_id_case_c1')),
          matching: find.textContaining('Waiting for ID'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Ask for ID says the case waits; its result says so', (
      t,
    ) async {
      // Round 3: a separate ID check case; this case keeps the rest.
      expect(kConfirmCaseAskForId, contains('separate ID check case'));
      expect(kConfirmCaseAskForId, contains('Waiting for ID'));
      await pumpHome(t);
      await _openCase(t);
      await t.ensureVisible(find.byKey(const ValueKey('console_ask_id')));
      await t.tap(find.byKey(const ValueKey('console_ask_id')));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(find.text(kConsoleAskedForId), findsOneWidget);
    });

    testWidgets('a case waiting for ID offers Lift hold (an adult), Confirm '
        'a minor and Dismiss, each confirmed', (t) async {
      final api = await pumpHome(
        t,
        answers: {
          'case': ConsoleAnswer(
            ok: true,
            // W7 final client fix (server round 3): the ID check is its own
            // case (kind id_check), with the server's id_check.
            data: {
              ..._caseIn('awaiting_id').data,
              'case': {
                ...(_caseIn('awaiting_id').data['case'] as Map),
                'kind': 'id_check',
                'id_check': {
                  'state': 'awaiting',
                  'restriction_live': true,
                  'code': 'AB23CD45',
                },
              },
              'reports': [
                {
                  'id': 'r1',
                  'category': 'underage_risk',
                  'priority': 'P0',
                  'state': 'open',
                },
              ],
            },
          ),
        },
      );
      await _openCase(t);
      expect(find.textContaining('waiting for ID'), findsWidgets);
      expect(find.text(kConsoleAwaitingIdNote), findsOneWidget);
      for (final key in [
        'console_claim',
        'console_hold',
        'console_restrict',
        'console_ask_id',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
      for (final (key, action, consequence) in [
        ('console_lift_hold', 'lift_hold', kConfirmLiftAgeCheck),
        ('console_minor', 'confirm_minor', kConfirmMinorIdCheck),
        ('console_dismiss', 'dismiss', kConfirmDismissIdCheck),
        ('console_no_id', 'close_no_id', kConfirmNoId),
      ]) {
        final button = find.byKey(ValueKey(key));
        await t.ensureVisible(button);
        await t.tap(button);
        await t.pumpAndSettle();
        expect(find.textContaining(consequence), findsOneWidget, reason: key);
        expect(
          Focus.of(t.element(find.text('Cancel'))).hasPrimaryFocus,
          isTrue,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(api.of(action), isEmpty, reason: key);
        await t.tap(button);
        await t.pumpAndSettle();
        await tapConfirm(t);
        expect(api.of(action), [
          {'case_id': 'c1'},
        ], reason: key);
      }
    });

    test('No ID came says it closes the case and keeps the age check; Lift '
        'hold there lifts only the age check', () {
      expect(kConfirmNoId, contains('closes this ID check'));
      expect(kConfirmNoId, contains('age check stays'));
      expect(kConfirmNoId, contains('until they verify'));
      expect(kConfirmLiftAgeCheck, isNot(contains('holds this case placed')));
      final line = consoleActionLine(
        'close_no_id',
        const ConsoleAnswer(ok: true),
      );
      expect(line.text, kConsoleClosedNoId);
    });

    testWidgets('a case no ID came for reads "Closed: no ID came"', (t) async {
      await pumpHome(
        t,
        answers: {
          'case': ConsoleAnswer(
            ok: true,
            data: {
              ...consoleCase.data,
              'case': {
                ...(consoleCase.data['case'] as Map),
                'state': 'decided',
                'outcome': 'no_id_received',
              },
              'prior': [
                {
                  'kind': 'report',
                  'state': 'decided',
                  'outcome': 'no_id_received',
                  'created_at': '2026-10-01',
                },
              ],
            },
          ),
        },
      );
      await _openCase(t);
      expect(find.textContaining('Closed: no ID came'), findsNWidgets(2));
      expect(find.textContaining('no_id_received'), findsNothing);
      expect(find.byKey(const ValueKey('console_no_id')), findsNothing);
    });

    testWidgets('a waiting case a new report joined follows its state', (
      t,
    ) async {
      await pumpHome(t, answers: {'case': _caseIn('in_review')});
      await _openCase(t);
      expect(find.byKey(const ValueKey('console_no_id')), findsNothing);
      expect(find.text(kConsoleAwaitingIdNote), findsNothing);
      expect(find.byKey(const ValueKey('console_ask_id')), findsOneWidget);
    });

    test('Dismiss on a case waiting for ID says it lifts the age check', () {
      expect(kConfirmDismissIdCheck, contains('the age check'));
      expect(kConfirmDismiss, isNot(contains('the age check')));
    });

    testWidgets('a case decided by its ID reads "ID checked: an adult", here '
        'and among earlier cases', (t) async {
      await pumpHome(
        t,
        answers: {
          'case': ConsoleAnswer(
            ok: true,
            data: {
              ...consoleCase.data,
              'case': {
                ...(consoleCase.data['case'] as Map),
                'state': 'decided',
                'outcome': 'id_verified',
              },
              'prior': [
                {
                  'kind': 'report',
                  'state': 'awaiting_id',
                  'outcome': null,
                  'created_at': '2026-11-01',
                },
                {
                  'kind': 'report',
                  'state': 'decided',
                  'outcome': 'id_verified',
                  'created_at': '2026-10-01',
                },
              ],
            },
          ),
        },
      );
      await _openCase(t);
      expect(find.textContaining('ID checked: an adult'), findsNWidgets(2));
      expect(find.textContaining('id_verified'), findsNothing);
      expect(find.textContaining('report · waiting for ID'), findsOneWidget);
      expect(find.textContaining('awaiting_id'), findsNothing);
    });

    testWidgets('a decided appeal or a decided case shows no Lift hold', (
      t,
    ) async {
      await pumpHome(t, answers: {'case': _caseIn('decided')});
      await _openCase(t);
      expect(find.byKey(const ValueKey('console_lift_hold')), findsNothing);
      expect(find.byKey(const ValueKey('console_minor')), findsNothing);
    });
  });
}
