// Spec 2 W7c Task 9, console round 3 (Task 8 fix round 1's replies; the
// Task 7 re-review's carries):
// - the safety owner's CSAM hold lift: the list, a written reason (code
//   points), a confirm that names the consequence, Cancel focused, Enter
//   and Esc cancel, nothing sent on cancel; a moderator's console asks
//   nothing;
// - a case's escalations, listed (the reference only when the server gives
//   it); consent_kind_required says what to record instead;
// - the case's Ask for ID and Lift hold confirm; a decided case can still
//   lift what it placed (an age check once support has seen the ID); no
//   line assumes one hold per person;
// - the law-enforcement log: emergency or legal process, the received day,
//   one received time per request however often Record is pressed, exists
//   decided through its id, a disclosure needs its categories, a decided
//   row opens with its decision;
// - sign-in: a code check that outlives its time box says so (never "That
//   code didn't work."); the copied key is cleared without reading the
//   clipboard; a tab store that refuses writes falls back to memory.
import 'dart:async';

import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:attune/console/console_session_storage.dart';
import 'package:attune/console/screens/case_screen.dart';
import 'package:attune/console/screens/console_lists.dart';
import 'package:attune/console/screens/law_enforcement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_fakes.dart';

const _hold = 'h1';

ConsoleAnswer _holds(List<Map<String, Object?>> holds) =>
    ConsoleAnswer(ok: true, data: {'ok': true, 'holds': holds});

final _oneHold = _holds([
  {
    'id': _hold,
    'since': '2026-11-20T10:00:00Z',
    'carried': true,
    'case_id': null,
    'escalations': [
      {
        'id': 'e-77',
        'status': 'reported',
        'created_at': '2026-11-20T10:05:00Z',
      },
    ],
  },
]);

ConsoleAnswer _caseIn(String state) => ConsoleAnswer(
  ok: true,
  data: {
    ...consoleCase.data,
    'case': {...(consoleCase.data['case'] as Map), 'state': state},
  },
);

ConsoleAnswer _log(List<Map<String, Object?>> rows) =>
    ConsoleAnswer(ok: true, data: {'ok': true, 'requests': rows});

/// Cancel focused; Cancel, Enter and Esc each send nothing.
Future<void> _cancelsThreeWays(
  WidgetTester t,
  Finder button,
  String consequence,
) async {
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
  expect(find.textContaining(consequence), findsOneWidget);
  expect(
    Focus.of(t.element(find.text('Cancel'))).hasPrimaryFocus,
    isTrue,
    reason: 'Cancel is the default focus',
  );
  await t.tap(find.byKey(const ValueKey('console_confirm_cancel')));
  await t.pumpAndSettle();
  await t.tap(button);
  await t.pumpAndSettle();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pumpAndSettle();
  await t.tap(button);
  await t.pumpAndSettle();
  await t.sendKeyEvent(LogicalKeyboardKey.escape);
  await t.pumpAndSettle();
  expect(find.textContaining(consequence), findsNothing);
}

/// An Auth whose code checks outlive their time box.
class _SlowAuth extends FakeConsoleAuth {
  _SlowAuth(super.state);

  @override
  Future<bool> verifyCode(String phone, String code) async {
    codes.add(code);
    throw TimeoutException('slow');
  }

  @override
  Future<bool> verifyTotp(String code, {String? factorId}) async {
    codes.add(code);
    throw TimeoutException('slow');
  }
}

/// A backend whose verifications never answer, or refuse.
class _Backend implements ConsoleAuthBackend {
  bool hang = true;

  Future<void> _answer() =>
      hang ? Completer<void>().future : Future.error(Exception('bad code'));

  @override
  bool get hasSession => true;

  @override
  bool get aal2 => false;

  @override
  Future<ConsoleTotpFactors> totpFactors() async => (
    verified: ['f1'],
    unverified: <String>[],
  );

  @override
  Future<void> sendSms(String phone, {required bool createUser}) async {}

  @override
  Future<void> verifySms(String phone, String code) => _answer();

  @override
  Future<ConsoleEnrolment?> enrolTotp(String issuer) async => null;

  @override
  Future<void> unenrol(String factorId) async {}

  @override
  Future<void> verifyTotp(String factorId, String code) => _answer();

  @override
  Future<void> signOut() async {}
}

/// sessionStorage that refuses writes (quota), or every call.
class _RefusingStore implements ConsoleTabStore {
  _RefusingStore({this.reads = true});

  final bool reads;
  final values = <String, String>{'sb-abc-auth-token': 'stale'};
  final removed = <String>[];

  @override
  String? read(String key) =>
      reads ? values[key] : throw StateError('SecurityError');

  @override
  void write(String key, String value) =>
      throw StateError('QuotaExceededError');

  @override
  void remove(String key) {
    removed.add(key);
    values.remove(key);
  }
}

void main() {
  group('the CSAM hold lift is the safety owner\'s', () {
    testWidgets('a moderator\'s console asks nothing of the list', (t) async {
      final api = await pumpHome(t, answers: {'csam_holds': _oneHold});
      await t.tap(find.text('CSAM holds'));
      await t.pumpAndSettle();
      expect(find.text(kConsoleCsamOwnerOnly), findsOneWidget);
      expect(api.of('csam_holds'), isEmpty);
      expect(api.of('lift_csam_hold'), isEmpty);
    });

    Future<FakeConsoleApi> open(WidgetTester t) async {
      final api = await pumpHome(
        t,
        me: consoleOwner,
        answers: {'csam_holds': _oneHold},
      );
      await t.tap(find.text('CSAM holds'));
      await t.pumpAndSettle();
      return api;
    }

    testWidgets('the owner sees each hold: since, carried, its Spec 1 '
        'reviews; an empty list says so', (t) async {
      final api = await open(t);
      expect(api.of('csam_holds'), [<String, Object?>{}]);
      expect(find.textContaining('20 Nov 2026, 10:00 UTC'), findsOneWidget);
      expect(find.textContaining('carried over'), findsOneWidget);
      expect(find.textContaining('e-77'), findsOneWidget);
      expect(find.textContaining('reported'), findsOneWidget);
      expect(
        find.textContaining('10:00 UTC · $kConsoleCsamFromHash'),
        findsOneWidget,
      );
      // Task 8 fix round 2: a report's or a moderator's csam-category hold
      // is listed too, by where it came from, never by its case's id.
      api.answers['csam_holds'] = _holds([
        {
          'id': 'h2',
          'since': '2026-11-21T10:00:00Z',
          'carried': false,
          'case_id': 'c-secret-9',
          'escalations': [],
        },
      ]);
      await t.tap(find.byKey(const ValueKey('console_refresh')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('10:00 UTC · $kConsoleCsamFromCase'),
        findsOneWidget,
      );
      expect(find.textContaining('c-secret-9'), findsNothing);
      expect(
        find.byKey(const ValueKey('console_csam_lift_h2')),
        findsOneWidget,
      );
      api.answers['csam_holds'] = _holds([]);
      await t.tap(find.byKey(const ValueKey('console_refresh')));
      await t.pumpAndSettle();
      expect(find.text('No CSAM hold is live.'), findsOneWidget);
    });

    testWidgets('a reason is required; Cancel at the reason sends nothing', (
      t,
    ) async {
      final api = await open(t);
      await t.tap(find.byKey(const ValueKey('console_csam_lift_$_hold')));
      await t.pumpAndSettle();
      final next = find.byKey(const ValueKey('console_csam_reason_next'));
      expect(t.widget<FilledButton>(next).onPressed, isNull);
      await t.enterText(
        find.byKey(const ValueKey('console_csam_reason')),
        '   ',
      );
      await t.pump();
      expect(t.widget<FilledButton>(next).onPressed, isNull);
      final field = t.widget<TextField>(
        find.byKey(const ValueKey('console_csam_reason')),
      );
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(api.of('lift_csam_hold'), isEmpty);
    });

    testWidgets('the reason is counted in code points, as the server counts '
        'it', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('console_csam_lift_$_hold')));
      await t.pumpAndSettle();
      final field = find.byKey(const ValueKey('console_csam_reason'));
      await t.enterText(field, '😀' * 1000);
      await t.pump();
      expect(find.text('1000 / 1000'), findsOneWidget);
      await t.enterText(field, '😀' * 1001);
      await t.pump();
      expect(t.widget<TextField>(field).controller!.text.runes.length, 1000);
    });

    testWidgets('the confirm names the consequence and the reason; Cancel, '
        'Enter and Esc send nothing; confirm sends once, trimmed', (t) async {
      final api = await open(t);
      final button = find.byKey(const ValueKey('console_csam_lift_$_hold'));
      Future<void> giveReason() async {
        await t.enterText(
          find.byKey(const ValueKey('console_csam_reason')),
          '  IWF confirmed a false positive.  ',
        );
        await t.pump();
        await t.tap(find.byKey(const ValueKey('console_csam_reason_next')));
        await t.pumpAndSettle();
      }

      for (final cancel in [
        () => t.tap(find.byKey(const ValueKey('console_confirm_cancel'))),
        () => t.sendKeyEvent(LogicalKeyboardKey.enter),
        () => t.sendKeyEvent(LogicalKeyboardKey.escape),
      ]) {
        await t.tap(button);
        await t.pumpAndSettle();
        await giveReason();
        expect(find.textContaining(kConfirmCsamLift), findsOneWidget);
        expect(
          find.textContaining('IWF confirmed a false positive.'),
          findsOneWidget,
        );
        expect(
          Focus.of(t.element(find.text('Cancel'))).hasPrimaryFocus,
          isTrue,
        );
        await cancel();
        await t.pumpAndSettle();
        expect(find.textContaining(kConfirmCsamLift), findsNothing);
      }
      expect(api.of('lift_csam_hold'), isEmpty);
      await t.tap(button);
      await t.pumpAndSettle();
      await giveReason();
      api.answers['csam_holds'] = _holds([]);
      await tapConfirm(t);
      expect(api.of('lift_csam_hold'), [
        {'restriction_id': _hold, 'reason': 'IWF confirmed a false positive.'},
      ]);
      expect(find.text(kConsoleCsamLifted), findsOneWidget);
      expect(api.of('csam_holds'), hasLength(2), reason: 'read again');
    });

    testWidgets('a hold that is gone says so; busy is calm', (t) async {
      final api = await open(t);
      Future<void> lift() async {
        await t.tap(find.byKey(const ValueKey('console_csam_lift_$_hold')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('console_csam_reason')),
          'A false positive.',
        );
        await t.pump();
        await t.tap(find.byKey(const ValueKey('console_csam_reason_next')));
        await t.pumpAndSettle();
        await tapConfirm(t);
      }

      api.answers['lift_csam_hold'] = const ConsoleAnswer(
        ok: false,
        reason: 'hold_unavailable',
      );
      await lift();
      expect(find.text(consoleReason('hold_unavailable')), findsOneWidget);
      api.answers['lift_csam_hold'] = ConsoleAnswer.busy;
      await lift();
      expect(find.text(consoleReason('busy')), findsOneWidget);
    });
  });

  group('the case', () {
    testWidgets('Ask for ID confirms first', (t) async {
      final api = await pumpHome(t);
      await t.tap(find.byKey(const ValueKey('console_case_c1')));
      await t.pumpAndSettle();
      final button = find.byKey(const ValueKey('console_ask_id'));
      await _cancelsThreeWays(t, button, kConfirmCaseAskForId);
      expect(api.of('ask_for_id'), isEmpty);
      await t.tap(button);
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(api.of('ask_for_id'), [
        {'case_id': 'c1'},
      ]);
    });

    // W7 final client fix (server round 2): an open case's holds lift with
    // Lift the case's holds (its own function); Lift hold is the ID path.
    testWidgets('Lift the case\'s holds confirms first, and never says the '
        'person has no hold left', (t) async {
      final api = await pumpHome(
        t,
        answers: {
          'lift_case_holds': const ConsoleAnswer(
            ok: true,
            data: {'ok': true, 'lifted': 1},
          ),
        },
      );
      await t.tap(find.byKey(const ValueKey('console_case_c1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console_lift_hold')), findsNothing);
      final button = find.byKey(const ValueKey('console_lift_case_holds'));
      await _cancelsThreeWays(t, button, kConfirmLiftCaseHoldsUnderage);
      expect(api.of('lift_case_holds'), isEmpty);
      await t.tap(button);
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(api.of('lift_case_holds'), [
        {'case_id': 'c1'},
      ]);
      expect(
        find.text("Lifted this case's hold. $kConsoleOtherHolds"),
        findsOneWidget,
      );
    });

    // Fix round 1 (owner: Ask for ID → awaiting_id; review M-8): a case
    // waiting for ID offers Lift hold, Confirm a minor and Dismiss; a
    // decided or closed case lifts nothing (a confirmed minor's age check
    // must not be lifted from its decided case).
    testWidgets('a case waiting for ID can lift; a decided or closed one '
        'cannot', (t) async {
      // W7 final client fix (server round 3): the ID check is its own case;
      // its Lift keys on the live check.
      final waiting = _caseIn('awaiting_id');
      final api = await pumpHome(
        t,
        answers: {
          'case': ConsoleAnswer(
            ok: true,
            data: {
              ...waiting.data,
              'case': {
                ...(waiting.data['case'] as Map),
                'kind': 'id_check',
                'id_check': {'state': 'awaiting', 'restriction_live': true},
              },
            },
          ),
        },
      );
      await t.tap(find.byKey(const ValueKey('console_case_c1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console_lift_hold')), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('console_lift_hold')));
      await t.tap(find.byKey(const ValueKey('console_lift_hold')));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(api.of('lift_hold'), hasLength(1));
      for (final state in ['decided', 'closed']) {
        api.answers['case'] = _caseIn(state);
        await t.tap(find.byKey(const ValueKey('console_refresh')));
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('console_lift_hold')),
          findsNothing,
          reason: state,
        );
      }
    });

    testWidgets('its escalations are listed: kind, date, who; the reference '
        'only when the server gives it', (t) async {
      final api = await pumpHome(
        t,
        answers: {
          'case_escalations': const ConsoleAnswer(
            ok: true,
            data: {
              'ok': true,
              'escalations': [
                {
                  'kind': 'police',
                  'recorded_at': '2026-11-21T09:00:00Z',
                  'mine': true,
                  'reference': 'GPS-1',
                },
                {
                  'kind': 'csa_292_with_consent',
                  'recorded_at': '2026-11-21T10:30:00Z',
                  'mine': false,
                },
              ],
            },
          ),
        },
      );
      await t.tap(find.byKey(const ValueKey('console_case_c1')));
      await t.pumpAndSettle();
      expect(api.of('case_escalations'), [
        {'case_id': 'c1'},
      ]);
      expect(
        find.text(
          'Police · recorded 21 Nov 2026, 09:00 UTC · by you · '
          'their reference: GPS-1',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "CSA 292, with the person's consent · recorded 21 Nov 2026, "
          '10:30 UTC',
        ),
        findsOneWidget,
      );
      api.answers['case_escalations'] = const ConsoleAnswer(
        ok: true,
        data: {'ok': true, 'escalations': []},
      );
      await t.tap(find.byKey(const ValueKey('console_refresh')));
      await t.pumpAndSettle();
      expect(find.text('None recorded.'), findsOneWidget);
      api.answers['case_escalations'] = ConsoleAnswer.busy;
      await t.tap(find.byKey(const ValueKey('console_refresh')));
      await t.pumpAndSettle();
      expect(find.text(kConsoleEscalationsUnread), findsOneWidget);
      expect(
        find.text('"She said she is in SHS."'),
        findsOneWidget,
        reason: 'the case itself still reads',
      );
    });

    testWidgets('an escalation: never learnt, counted in code points, read '
        'again after; a sextortion case says to use the consent kind', (
      t,
    ) async {
      final api = await pumpHome(
        t,
        answers: {
          'escalate': const ConsoleAnswer(
            ok: false,
            reason: 'consent_kind_required',
          ),
        },
      );
      await t.tap(find.byKey(const ValueKey('console_case_c1')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('console_escalate')));
      await t.tap(find.byKey(const ValueKey('console_escalate')));
      await t.pumpAndSettle();
      expect(find.text(kConsoleEscalationRecordOnly), findsOneWidget);
      final ref = find.byKey(const ValueKey('console_escalation_reference'));
      final field = t.widget<TextField>(ref);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      await t.enterText(ref, '😀' * 201);
      await t.pump();
      expect(t.widget<TextField>(ref).controller!.text.runes.length, 200);
      await t.tap(find.byKey(const ValueKey('console_escalation_kind')));
      await t.pumpAndSettle();
      await t.tap(find.text('Cyber Security Authority').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_escalation_save')));
      await t.pumpAndSettle();
      expect(api.of('escalate').single['kind'], 'csa');
      expect(find.text(consoleReason('consent_kind_required')), findsOneWidget);
      expect(api.of('case_escalations'), hasLength(2), reason: 'read again');
    });
  });

  group('the law-enforcement log', () {
    Future<FakeConsoleApi> open(
      WidgetTester t, {
      Map<String, ConsoleAnswer> answers = const {},
    }) async {
      final api = await pumpHome(t, me: consoleOwner, answers: answers);
      await t.tap(find.text('Law enforcement'));
      await t.pumpAndSettle();
      return api;
    }

    Future<void> fill(WidgetTester t) async {
      await t.enterText(
        find.byKey(const ValueKey('console_le_jurisdiction')),
        'gh',
      );
      await t.enterText(
        find.byKey(const ValueKey('console_le_basis')),
        'Court order',
      );
      await t.enterText(
        find.byKey(const ValueKey('console_le_scope')),
        'One account',
      );
    }

    testWidgets('an emergency and the day it came; a retry after busy sends '
        'the same request; a recorded one clears the form', (t) async {
      final api = await open(t, answers: {'le_record': ConsoleAnswer.busy});
      await fill(t);
      await t.tap(find.byKey(const ValueKey('console_le_emergency')));
      await t.tap(find.byKey(const ValueKey('console_le_record')));
      await t.pumpAndSettle();
      expect(find.text(consoleReason('busy')), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      api.answers['le_record'] = const ConsoleAnswer(
        ok: true,
        data: {'ok': true, 'id': 'l9'},
      );
      await t.tap(find.byKey(const ValueKey('console_le_record')));
      await t.pumpAndSettle();
      final sent = api.of('le_record');
      expect(sent, hasLength(2));
      final first = sent.first['values']! as Map<String, Object?>;
      expect(first['emergency'], isTrue);
      expect(
        sent.last['values'],
        first,
        reason: 'one request, one received time: the server replays it',
      );
      expect(find.text('Recorded.'), findsOneWidget);
      final country = t.widget<TextField>(
        find.byKey(const ValueKey('console_le_jurisdiction')),
      );
      expect(country.controller!.text, isEmpty);
      final day = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 3))
          .toIso8601String()
          .substring(0, 10);
      await fill(t);
      await t.enterText(find.byKey(const ValueKey('console_le_received')), day);
      await t.tap(find.byKey(const ValueKey('console_le_record')));
      await t.pumpAndSettle();
      final last = api.of('le_record').last['values']! as Map<String, Object?>;
      // Fix round 1 (review M-1): the typed day, at a time of its own.
      expect(last['received_at'], startsWith('${day}T'));
      expect(last['emergency'], isFalse);
      expect(last, isNot(contains('decision')));
    });

    testWidgets('a form that isn\'t whole sends nothing, and says why', (
      t,
    ) async {
      final api = await open(t);
      final record = find.byKey(const ValueKey('console_le_record'));
      await t.tap(record);
      await t.pumpAndSettle();
      expect(find.text(kConsoleRequestNotWhole), findsOneWidget);
      await fill(t);
      await t.enterText(
        find.byKey(const ValueKey('console_le_jurisdiction')),
        'Ghana',
      );
      await t.tap(record);
      await t.pumpAndSettle();
      await fill(t);
      await t.enterText(
        find.byKey(const ValueKey('console_le_received')),
        '2026-02-31',
      );
      await t.tap(record);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('console_le_scope')), ' ');
      await t.enterText(find.byKey(const ValueKey('console_le_received')), '');
      await t.tap(record);
      await t.pumpAndSettle();
      expect(api.of('le_record'), isEmpty);
      expect(find.text(kConsoleRequestNotWhole), findsOneWidget);
    });

    testWidgets('exists is decided through the logged request\'s id', (
      t,
    ) async {
      final api = await open(
        t,
        answers: {
          'le_record': const ConsoleAnswer(
            ok: false,
            reason: 'exists',
            data: {'ok': false, 'reason': 'exists', 'id': 'l1'},
          ),
        },
      );
      await fill(t);
      await t.tap(find.byKey(const ValueKey('console_le_record')));
      await t.pumpAndSettle();
      expect(find.text(consoleReason('exists')), findsOneWidget);
      api.answers['le_record'] = const ConsoleAnswer(ok: true);
      await t.tap(find.byKey(const ValueKey('console_le_exists_decide')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_le_decision')));
      await t.pumpAndSettle();
      await t.tap(find.text('Refused').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_le_decide_save')));
      await t.pumpAndSettle();
      expect(api.of('le_record').last, {
        'request_id': 'l1',
        'values': {
          'decision': 'refused',
          'disclosed_categories': <String>[],
          'user_notified': false,
        },
      });
    });

    testWidgets('a pending request waits for a decision; a disclosure needs '
        'what was disclosed; a refusal sends none', (t) async {
      final api = await open(
        t,
        answers: {
          'le_requests': _log([
            {
              'id': 'l1',
              'jurisdiction': 'GH',
              'decision': 'pending',
              'received_at': '2026-11-20T08:00:00Z',
              'legal_basis': 'Court order',
              'scope': 'One account',
              'emergency': false,
              'disclosed_categories': [],
            },
          ]),
        },
      );
      await t.tap(find.text('Decide'));
      await t.pumpAndSettle();
      final save = find.byKey(const ValueKey('console_le_decide_save'));
      expect(t.widget<FilledButton>(save).onPressed, isNull);
      await t.tap(find.byKey(const ValueKey('console_le_decision')));
      await t.pumpAndSettle();
      await t.tap(find.text('Disclosed').last);
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(save).onPressed, isNull);
      expect(find.text(kConsoleDisclosureFinal), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('console_le_disclosed_messages')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_le_decision')));
      await t.pumpAndSettle();
      await t.tap(find.text('Contested').last);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('console_le_disclosed_messages')),
        findsNothing,
      );
      await t.tap(save);
      await t.pumpAndSettle();
      expect(api.of('le_record').single, {
        'request_id': 'l1',
        'values': {
          'decision': 'contested',
          'disclosed_categories': <String>[],
          'user_notified': false,
        },
      });
    });

    testWidgets('a decided row opens with its decision; the notice alone can '
        'be added; a narrowed disclosure is refused', (t) async {
      final api = await open(
        t,
        answers: {
          'le_requests': _log([
            {
              'id': 'l2',
              'jurisdiction': 'NG',
              'decision': 'partly_disclosed',
              'received_at': '2026-11-18T08:00:00Z',
              'legal_basis': 'Warrant',
              'scope': 'Messages',
              'emergency': true,
              'disclosed_categories': ['account', 'messages'],
              'decided_at': '2026-11-19T08:00:00Z',
            },
          ]),
          'le_record': const ConsoleAnswer(
            ok: false,
            reason: 'already_disclosed',
          ),
        },
      );
      expect(find.textContaining('emergency'), findsOneWidget);
      expect(find.textContaining('account, messages'), findsOneWidget);
      await t.tap(find.text('Decide'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_le_told')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_le_decide_save')));
      await t.pumpAndSettle();
      expect(api.of('le_record').single, {
        'request_id': 'l2',
        'values': {
          'decision': 'partly_disclosed',
          'disclosed_categories': ['account', 'messages'],
          'user_notified': true,
        },
      });
      expect(find.text(consoleReason('already_disclosed')), findsOneWidget);
    });

    testWidgets('a window that isn\'t two days sends nothing; the summary '
        'says its counts are raw', (t) async {
      final api = await open(
        t,
        answers: {
          'transparency': const ConsoleAnswer(
            ok: true,
            data: {
              'ok': true,
              'summary': {'requests_met': 1},
            },
          ),
        },
      );
      final from = find.byKey(const ValueKey('console_le_from'));
      final to = find.byKey(const ValueKey('console_le_to'));
      final count = find.byKey(const ValueKey('console_le_summary'));
      await t.ensureVisible(from);
      await t.enterText(from, '2026-7-1');
      await t.enterText(to, '2026-10-01');
      await t.ensureVisible(count);
      await t.tap(count);
      await t.pumpAndSettle();
      expect(api.of('transparency'), isEmpty);
      expect(find.text(kConsoleWindowDays), findsOneWidget);
      await t.enterText(from, '2026-07-01');
      await t.tap(count);
      await t.pumpAndSettle();
      expect(api.of('transparency'), hasLength(1));
      expect(find.text(kConsoleSummaryRaw), findsOneWidget);
    });
  });

  group('sign-in', () {
    testWidgets('a code check that outlives its time box says so, calmly; '
        'Check my sign-in reads the session again', (t) async {
      final auth = _SlowAuth(ConsoleSession.signedOut);
      await t.pumpWidget(ConsoleApp(api: FakeConsoleApi({}), auth: auth));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('console_phone')),
        '+233244000000',
      );
      await t.tap(find.byKey(const ValueKey('console_next')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('console_code')), '123456');
      await t.tap(find.byKey(const ValueKey('console_next')));
      await t.pumpAndSettle();
      expect(find.text("That code didn't work."), findsNothing);
      expect(find.text(kConsoleSlowCheck), findsOneWidget);
      final colour = t.widget<Text>(find.text(kConsoleSlowCheck)).style?.color;
      final theme = Theme.of(t.element(find.text(kConsoleSlowCheck)));
      expect(colour, isNot(theme.colorScheme.error));
      auth.state = ConsoleSession.needsTotp; // the late check went through
      await t.tap(find.byKey(const ValueKey('console_check_again')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console_totp')), findsOneWidget);
      expect(find.text(kConsoleSlowCheck), findsNothing);
      await t.enterText(find.byKey(const ValueKey('console_totp')), '654321');
      await t.tap(find.byKey(const ValueKey('console_verify')));
      await t.pumpAndSettle();
      expect(find.text(kConsoleSlowCheck), findsOneWidget);
      expect(find.text("That code didn't work."), findsNothing);
    });

    test('SupabaseConsoleAuth: a slow check is a timeout, a refused one is '
        'false', () async {
      final b = _Backend();
      final auth = SupabaseConsoleAuth.using(
        b,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        auth.verifyCode('+233244000000', '123456'),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        auth.verifyTotp('654321'),
        throwsA(isA<TimeoutException>()),
      );
      b.hang = false;
      expect(await auth.verifyCode('+233244000000', '123456'), isFalse);
      expect(await auth.verifyTotp('654321'), isFalse);
    });

    testWidgets('the copied key is cleared without reading the clipboard, '
        'and only when this console copied it', (t) async {
      final calls = <String>[];
      String? clip;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData' ||
              call.method == 'Clipboard.getData') {
            calls.add(call.method);
          }
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clip};
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      Future<void> enrol({required bool copy}) async {
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(
          ConsoleApp(
            api: FakeConsoleApi({'whoami': consoleMe, 'queue': consoleQueue}),
            auth: FakeConsoleAuth(ConsoleSession.needsEnrol),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('console_enrol')));
        await t.pumpAndSettle();
        if (copy) {
          await t.tap(find.byKey(const ValueKey('console_copy_key')));
          await t.pumpAndSettle();
          expect(find.text(kConsoleClipboardHint), findsOneWidget);
        }
      }

      await enrol(copy: true);
      clip = 'something copied later';
      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      expect(clip, isEmpty);
      expect(calls, isNot(contains('Clipboard.getData')));
      calls.clear();
      await enrol(copy: false);
      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      expect(calls, isEmpty, reason: 'never copied, never touched');
    });

    test('a tab store that refuses writes falls back to memory, without an '
        'unhandled error', () async {
      final refusing = _RefusingStore();
      final store = ConsoleSafeTabStore(refusing);
      final s = ConsoleSessionStorage(store, key: 'sb-abc-auth-token');
      await s.persistSession('{"access_token":"a"}');
      expect(await s.accessToken(), '{"access_token":"a"}');
      expect(refusing.removed, [
        'sb-abc-auth-token',
      ], reason: 'the stale session it held is not read again');
      await s.persistSession('{"access_token":"b"}');
      expect(await s.accessToken(), '{"access_token":"b"}');
      await s.removePersistedSession();
      expect(await s.hasAccessToken(), isFalse);

      final unreadable = ConsoleSafeTabStore(_RefusingStore(reads: false));
      expect(unreadable.read('k'), isNull);
      unreadable.write('k', 'v');
      expect(unreadable.read('k'), 'v');

      final fine = MemoryTabStore();
      final kept = ConsoleSafeTabStore(fine)..write('k', 'v');
      expect(fine.values, {'k': 'v'}, reason: 'a store that works is used');
      expect(kept.read('k'), 'v');
    });
  });

  test('a refusal keeps nothing but its code; exists keeps its id', () {
    final r = ConsoleAnswer.fromJson({
      'ok': false,
      'reason': 'exists',
      'id': 'l1',
      'scope': 'One account',
    });
    expect(r.ok, isFalse);
    expect(r.reason, 'exists');
    expect(r.data, {'id': 'l1'});
    expect(
      ConsoleAnswer.fromJson({
        'ok': false,
        'reason': 'invalid',
        'id': 'l1',
      }).data,
      isEmpty,
    );
  });

  test('the lift lines never say the person has no hold left', () {
    for (final n in [0, 1, 3]) {
      final line = consoleActionLine(
        'lift_hold',
        ConsoleAnswer(ok: true, data: {'ok': true, 'lifted': n}),
      );
      expect(line.text, endsWith(kConsoleOtherHolds), reason: '$n');
    }
    // Task 8 fix round 2: Lift hold never ends a CSAM hold; only the safety
    // owner's CSAM lift does, and the copy says so.
    for (final copy in [kConsoleOtherHolds, kConfirmLiftCaseHolds]) {
      expect(copy, contains("only the safety owner's CSAM lift"));
    }
  });
}
