// Spec 2 W7 final client fix (final-client-review.md), the console's items:
// - I-5 (server round 3: the ID check is its own case, kind id_check):
//   an ID check case shows its code, its moved age reports and a link to
//   the case it came from, and offers only Lift the age check, Confirm a
//   minor, No ID came and Dismiss (asked by mistake), each confirmed with
//   its consequence; a decided No ID came check whose age check is live
//   still lifts and confirms a minor; Hold, Restrict and Ask for ID never
//   show there; an ordinary case is plain again (Dismiss, Confirm a minor,
//   Lift the case's holds), Ask for ID says it opens a separate ID check
//   and the case links to it; the Queue page reads each kind (p_kind) and
//   lists "Waiting for ID / ID still needed" (p_kind id_check) first;
//   has_more says more are waiting; invalid has its own line;
// - I-6: the ID check's code on the case and its queue row;
// - M-1: lifting an underage case's holds says when to lift an age check;
// - M-2: a waiting row never says "late";
// - M-3: Accept says what stays, Reject says Done;
// - M-7: a read again that fails keeps the rows and the action's line;
// - M-8: Accept and Reject are off when the server would refuse them;
// - M-9: Accept says Dating stays paused (R-53);
// - M-10: the two Ask for ID actions have two names;
// - M-11: Restrict says what follows the type and length picked.
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:attune/console/screens/case_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_fakes.dart';

/// Answers each queue read by its kind (an empty list for a kind not set).
class _KindApi extends FakeConsoleApi {
  _KindApi(super.answers, this.byKind);

  final Map<String, ConsoleAnswer> byKind;

  @override
  Future<ConsoleAnswer> call(
    String action, [
    Map<String, Object?> params = const {},
  ]) async {
    if (action != 'queue') return super.call(action, params);
    calls.add((action, params));
    return byKind[params['kind']] ??
        const ConsoleAnswer(ok: true, data: {'ok': true, 'cases': []});
  }
}

ConsoleAnswer _cases(List<Map<String, Object?>> rows, {bool? more}) =>
    ConsoleAnswer(
      ok: true,
      data: {'ok': true, 'cases': rows, if (more != null) 'has_more': more},
    );

const _live = {'state': 'awaiting', 'restriction_live': true, 'code': 'AB23CD45'};
const _noId = {'state': 'no_id', 'restriction_live': true, 'code': 'XY67ZW89'};
const _notLive = {'state': null, 'restriction_live': false, 'code': null};

final _past = DateTime.now().subtract(const Duration(hours: 30));

Map<String, Object?> _row(
  String id, {
  String state = 'open',
  Map<String, Object?>? idCheck,
  String kind = 'report',
  String priority = 'P1',
}) => {
  'id': id,
  'kind': kind,
  'priority': priority,
  'category': 'underage_risk',
  'state': state,
  'reports': 1,
  'sla_due_at': _past.toIso8601String(),
  'created_at': '2026-11-20T09:00:00Z',
  'mine': false,
  'claimed': false,
  'gone': false,
  'id_check': idCheck,
};

ConsoleAnswer _case({
  required String state,
  String kind = 'report',
  Map<String, Object?>? idCheck,
  String? outcome,
  String? origin,
  String? idCase,
  List<Map<String, Object?>> reports = const [
    {'id': 'r1', 'category': 'underage_risk', 'priority': 'P0', 'state': 'open'},
  ],
}) => ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'case': {
      'id': 'c1',
      'kind': kind,
      'priority': 'P0',
      'state': state,
      if (outcome != null) 'outcome': outcome,
      'mine': true,
      if (idCheck != null) 'id_check': idCheck,
      'origin_case': origin,
      'id_case': idCase,
    },
    'reports': reports,
    'appeal': null,
  },
);

Future<_KindApi> _home(
  WidgetTester t, {
  ConsoleAnswer me = consoleMe,
  Map<String, ConsoleAnswer> answers = const {},
  Map<String, ConsoleAnswer> queue = const {},
}) async {
  await t.pumpWidget(const SizedBox());
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final api = _KindApi({'whoami': me, 'case': consoleCase, ...answers}, {
    'report': _cases([_row('c1')]),
    ...queue,
  });
  await t.pumpWidget(
    ConsoleApp(api: api, auth: FakeConsoleAuth(ConsoleSession.ready)),
  );
  await t.pumpAndSettle();
  return api;
}

Future<void> _open(WidgetTester t, String key) async {
  await t.tap(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
  expect(find.text('Case'), findsOneWidget, reason: 'the case page first');
}

Finder _key(String k) => find.byKey(ValueKey(k));

bool _on(WidgetTester t, String key) =>
    t.widget<ButtonStyleButton>(_key(key)).onPressed != null;

Future<String> _confirmText(WidgetTester t, String key) async {
  await t.ensureVisible(_key(key));
  await t.tap(_key(key));
  await t.pumpAndSettle();
  final text = t.widget<Text>(_key('console_confirm_text')).data!;
  await t.tap(_key('console_confirm_cancel'));
  await t.pumpAndSettle();
  return text;
}

void main() {
  group('I-5 (round 3): the ID check is its own case', () {
    const oneAge = [
      {'id': 'r1', 'category': 'underage_risk', 'priority': 'P0', 'state': 'open'},
    ];

    testWidgets('a waiting ID check: its code, its age reports, the case it '
        'came from; only its four actions, each confirmed with its '
        'consequence', (t) async {
      final api = await _home(
        t,
        answers: {
          'case': _case(
            state: 'awaiting_id',
            kind: 'id_check',
            idCheck: _live,
            origin: 'c0',
            reports: oneAge,
          ),
        },
      );
      await _open(t, 'console_case_c1');
      expect(find.textContaining('P0 · ID check · waiting for ID'), findsOneWidget);
      expect(
        t.widget<SelectableText>(_key('console_id_code')).data,
        'ID check code: AB23CD45',
      );
      expect(t.widget<Text>(_key('console_id_note')).data, kConsoleAwaitingIdNote);
      expect(find.textContaining('underage_risk'), findsWidgets);
      for (final k in [
        'console_hold',
        'console_restrict',
        'console_ask_id',
        'console_lift_case_holds',
        'console_id_case',
      ]) {
        expect(_key(k), findsNothing, reason: k);
      }
      for (final (key, label, copy) in [
        ('console_lift_hold', kConsoleLiftAgeCheck, kConfirmLiftAgeCheck),
        ('console_minor', 'Confirm a minor', kConfirmMinorIdCheck),
        ('console_no_id', 'No ID came', kConfirmNoId),
        ('console_dismiss', kConsoleDismissIdCheck, kConfirmDismissIdCheck),
      ]) {
        expect(
          find.descendant(of: _key(key), matching: find.text(label)),
          findsOneWidget,
          reason: key,
        );
        expect(await _confirmText(t, key), copy, reason: key);
      }
      for (final copy in [kConfirmLiftAgeCheck, kConfirmDismissIdCheck]) {
        expect(copy, contains(kConsoleNotOrigin));
        expect(copy, isNot(contains('back in introductions')));
      }
      await t.tap(_key('console_no_id'));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(api.of('close_no_id'), [
        {'case_id': 'c1'},
      ]);
      // The case it came from opens from here.
      api.answers['case'] = _case(state: 'in_review', idCase: 'c1');
      await t.ensureVisible(_key('console_origin_case'));
      await t.tap(_key('console_origin_case'));
      await t.pumpAndSettle();
      expect(api.of('case').last, {'case_id': 'c0'});
      expect(_key('console_id_case'), findsOneWidget);
    });

    testWidgets('a decided No ID came check whose age check is live: ID '
        'still needed; a late ID lifts it (the decision stands) and Confirm '
        'a minor stays', (t) async {
      final api = await _home(
        t,
        answers: {
          'case': _case(
            state: 'decided',
            kind: 'id_check',
            outcome: 'no_id_received',
            idCheck: _noId,
            reports: const [
              {'id': 'r1', 'category': 'underage_risk', 'priority': 'P0', 'state': 'upheld'},
            ],
          ),
        },
      );
      await _open(t, 'console_case_c1');
      expect(
        t.widget<Text>(_key('console_id_note')).data,
        kConsoleIdStillNeededNote,
      );
      expect(_key('console_no_id'), findsNothing);
      expect(_key('console_dismiss'), findsNothing);
      expect(_key('console_minor'), findsOneWidget);
      expect(await _confirmText(t, 'console_lift_hold'), kConfirmLiftIdDecided);
      await t.tap(_key('console_lift_hold'));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(api.of('lift_hold'), [
        {'case_id': 'c1'},
      ]);
    });

    testWidgets('a decided ID check whose age check ended offers nothing',
        (t) async {
      await _home(
        t,
        answers: {
          'case': _case(
            state: 'decided',
            kind: 'id_check',
            outcome: 'id_verified',
            idCheck: _notLive,
          ),
        },
      );
      await _open(t, 'console_case_c1');
      for (final k in [
        'console_no_id',
        'console_lift_hold',
        'console_lift_case_holds',
        'console_minor',
        'console_dismiss',
        'console_id_note',
        'console_id_code',
      ]) {
        expect(_key(k), findsNothing, reason: k);
      }
    });

    testWidgets('an ordinary case is plain: Dismiss, Confirm a minor (an open '
        "age report), Lift the case's holds, Ask for ID; no ID actions, even "
        'with a stray id_check; it links to its ID check', (t) async {
      final api = await _home(
        t,
        answers: {
          'case': _case(
            state: 'in_review',
            idCheck: _live,
            idCase: 'c9',
            reports: oneAge,
          ),
          'ask_for_id': const ConsoleAnswer(
            ok: true,
            data: {'ok': true, 'id_case': 'c9'},
          ),
        },
      );
      await _open(t, 'console_case_c1');
      expect(_key('console_no_id'), findsNothing);
      expect(_key('console_lift_hold'), findsNothing);
      expect(_key('console_id_note'), findsNothing);
      expect(_key('console_id_code'), findsNothing);
      expect(await _confirmText(t, 'console_dismiss'), kConfirmDismiss);
      expect(await _confirmText(t, 'console_minor'), kConfirmMinor);
      expect(
        await _confirmText(t, 'console_lift_case_holds'),
        kConfirmLiftCaseHoldsUnderage,
      );
      final ask = await _confirmText(t, 'console_ask_id');
      expect(ask, kConfirmCaseAskForId);
      expect(ask, contains('separate ID check case'));
      expect(ask, contains('age reports move there'));
      await t.tap(_key('console_ask_id'));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(t.widget<Text>(_key('console_case_line')).data, kConsoleAskedForId);
      await t.ensureVisible(_key('console_id_case'));
      await t.tap(_key('console_id_case'));
      await t.pumpAndSettle();
      expect(api.of('case').last, {'case_id': 'c9'});
    });

    testWidgets('an ordinary case with no open age report offers no Confirm '
        "a minor; Lift the case's holds sends its own action", (t) async {
      final api = await _home(
        t,
        answers: {
          'case': _case(
            state: 'in_review',
            reports: const [
              {'id': 'r2', 'category': 'harassment', 'priority': 'P2', 'state': 'open'},
            ],
          ),
        },
      );
      await _open(t, 'console_case_c1');
      expect(_key('console_minor'), findsNothing);
      expect(
        await _confirmText(t, 'console_lift_case_holds'),
        kConfirmLiftCaseHolds,
      );
      await t.tap(_key('console_lift_case_holds'));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(api.of('lift_case_holds'), [
        {'case_id': 'c1'},
      ]);
      expect(api.of('lift_hold'), isEmpty);
    });

    for (final idCheck in [_live, _notLive]) {
      testWidgets('round 4: an orphaned ID check (the person deleted their '
          'account) offers only No ID came, which says the age check stays '
          "on their number (live: ${idCheck['restriction_live']})", (t) async {
        final api = await _home(
          t,
          answers: {
            'case': ConsoleAnswer(
              ok: true,
              data: {
                ..._case(
                  state: 'awaiting_id',
                  kind: 'id_check',
                  idCheck: idCheck,
                  reports: oneAge,
                ).data,
                'case': {
                  ...(_case(
                            state: 'awaiting_id',
                            kind: 'id_check',
                            idCheck: idCheck,
                          ).data['case']
                          as Map),
                  'gone': true,
                },
              },
            ),
          },
        );
        await _open(t, 'console_case_c1');
        expect(find.text('The account was deleted.'), findsOneWidget);
        for (final k in [
          'console_lift_hold',
          'console_dismiss',
          'console_minor',
          'console_hold',
          'console_restrict',
          'console_ask_id',
          'console_lift_case_holds',
        ]) {
          expect(_key(k), findsNothing, reason: k);
        }
        final copy = await _confirmText(t, 'console_no_id');
        expect(copy, kConfirmNoIdGone);
        expect(copy, contains('phone number'));
        expect(copy, contains('if they return'));
        await t.tap(_key('console_no_id'));
        await t.pumpAndSettle();
        await tapConfirm(t);
        expect(api.of('close_no_id'), [
          {'case_id': 'c1'},
        ]);
      });
    }

    test('the state derives from the ID track\'s outcome; a check that '
        'isn\'t live is nothing', () {
      expect(
        ConsoleIdCheck.of({
          'restriction_live': true,
          'outcome': 'no_id_received',
        }).stillNeeded,
        isTrue,
      );
      expect(
        ConsoleIdCheck.of({'restriction_live': true, 'outcome': null}).state,
        'awaiting',
      );
      final gone = ConsoleIdCheck.of({
        'restriction_live': false,
        'outcome': 'id_verified',
        'state': 'no_id',
        'code': 'AB23CD45',
      });
      expect(gone.live, isFalse);
      expect(gone.code, isNull);
      expect(consoleCaseKind('id_check'), 'ID check');
      expect(consoleCaseOutcome('asked_for_id'), isNot('asked_for_id'));
    });

    testWidgets('I-6: the case shows its ID check code, selectable', (t) async {
      await _home(
        t,
        answers: {
          'case': _case(state: 'awaiting_id', kind: 'id_check', idCheck: _live),
        },
      );
      await _open(t, 'console_case_c1');
      expect(
        t.widget<SelectableText>(_key('console_id_code')).data,
        'ID check code: AB23CD45',
      );
    });
  });

  group('I-5: the queue', () {
    testWidgets('each kind is its own read; Waiting for ID / ID still '
        'needed comes first with each code, decided cases too, never a '
        'clock or "late" (M-2)', (t) async {
      final api = await _home(
        t,
        queue: {
          'id_check': _cases([
            _row('w1', kind: 'id_check', state: 'awaiting_id', idCheck: _live),
            _row('n1', kind: 'id_check', state: 'decided', idCheck: _noId),
            // A row of another kind never sits in the section.
            _row('x1', state: 'in_review'),
          ]),
          'report': _cases([
            _row('c1', priority: 'P0'),
          ]),
        },
      );
      expect(find.text(kConsoleIdSection), findsOneWidget);
      expect(
        api.of('queue').map((q) => q['kind']),
        ['id_check', 'report', 'photo', 'verification', 'csam_hit'],
      );
      final waiting = _key('console_id_case_w1');
      final still = _key('console_id_case_n1');
      expect(waiting, findsOneWidget);
      expect(still, findsOneWidget);
      expect(_key('console_id_case_x1'), findsNothing);
      String subtitle(Finder f) =>
          (t.widget<ListTile>(f).subtitle! as Text).data!;
      expect(subtitle(waiting), contains('Waiting for ID'));
      expect(subtitle(waiting), contains('ID check code: AB23CD45'));
      expect(subtitle(still), contains('ID still needed'));
      expect(subtitle(still), contains('ID check code: XY67ZW89'));
      for (final s in [subtitle(waiting), subtitle(still)]) {
        expect(s, isNot(contains('late')));
        // Round 3: an ID check opens at Ask for ID, so its date is the ask.
        expect(s, contains('asked for ID 20 Nov 2026, 09:00 UTC'));
      }
      expect(
        (t.widget<ListTile>(waiting).title! as Text).data,
        'P1 · ID check · underage_risk',
      );
      // The ordinary case has its clock below.
      expect(_key('console_case_w1'), findsNothing);
      expect(_key('console_case_c1'), findsOneWidget);
      expect(
        (t.widget<ListTile>(_key('console_case_c1')).subtitle! as Text).data,
        contains('late'),
      );
      expect(
        t.getTopLeft(find.text(kConsoleIdSection)).dy,
        lessThan(t.getTopLeft(_key('console_case_c1')).dy),
      );
      // A decided case offers no Claim.
      expect(
        find.descendant(of: still, matching: find.byType(TextButton)),
        findsNothing,
      );
      await _open(t, 'console_id_case_n1');
    });

    test('final minor 2: the cap line says it is per kind', () {
      expect(kConsoleQueueCapped, contains('the first 200 of this kind'));
      expect(kConsoleQueueCapped, isNot(contains('200 open cases')));
    });

    testWidgets('has_more on any read says more are waiting; a page of '
        'its own kinds only', (t) async {
      await _home(
        t,
        queue: {
          'appeal': _cases([
            _row('a1', kind: 'appeal'),
          ], more: true),
        },
      );
      expect(find.text(kConsoleQueueCapped), findsNothing);
      await t.tap(find.text('Appeals'));
      await t.pumpAndSettle();
      expect(find.text(kConsoleQueueCapped), findsOneWidget);
      expect(_key('console_case_a1'), findsOneWidget);
      expect(find.text(kConsoleIdSection), findsNothing);
    });

    testWidgets('invalid (a server that doesn\'t know the kind) has its own '
        'line and Try again', (t) async {
      await _home(
        t,
        queue: {'id_check': const ConsoleAnswer(ok: false, reason: 'invalid')},
      );
      expect(find.text(kConsoleQueueInvalid), findsOneWidget);
      expect(_key('console_retry'), findsOneWidget);
    });

    testWidgets('M-7: a claim whose read again is busy keeps its line and '
        'the rows, under Try again', (t) async {
      final api = await _home(t);
      expect(_key('console_case_c1'), findsOneWidget);
      api.byKind['report'] = ConsoleAnswer.busy;
      await t.tap(find.text('Claim'));
      await t.pumpAndSettle();
      expect(find.text('Claimed: the case is yours.'), findsOneWidget);
      expect(_key('console_case_c1'), findsOneWidget);
      expect(_key('console_retry'), findsOneWidget);
      expect(find.text(consoleReason('busy')), findsOneWidget);
    });
  });

  group('the case\'s minors', () {
    testWidgets("M-1: Lift the case's holds on an underage case says when to "
        'lift an age check; on another, nothing of it', (t) async {
      await _home(t, answers: {'case': _case(state: 'in_review')});
      await _open(t, 'console_case_c1');
      expect(
        await _confirmText(t, 'console_lift_case_holds'),
        kConfirmLiftCaseHoldsUnderage,
      );
      expect(
        kConfirmLiftCaseHoldsUnderage,
        endsWith("Lift an age check only once support has seen this person's ID."),
      );
      await _home(
        t,
        answers: {
          'case': _case(
            state: 'in_review',
            reports: const [
              {'id': 'r1', 'category': 'spam', 'priority': 'P3', 'state': 'open'},
            ],
          ),
        },
      );
      await _open(t, 'console_case_c1');
      expect(
        await _confirmText(t, 'console_lift_case_holds'),
        kConfirmLiftCaseHolds,
      );
    });

    ConsoleAnswer appeal({
      bool mine = false,
      bool known = true,
      String sent = '2026-11-21T10:00:00Z',
    }) => ConsoleAnswer(
      ok: true,
      data: {
        'ok': true,
        'case': {'id': 'c3', 'kind': 'appeal', 'priority': 'P2', 'state': 'open'},
        'reports': [],
        'appeal': {
          'text': 'I did not.',
          'submitted_at': sent,
          'restriction': {
            'type': 'suspended',
            'category': 'harassment',
            'ends_at': null,
            'decided_by_me': mine,
            'decider_known': known,
          },
        },
      },
    );

    Future<_KindApi> appealPage(
      WidgetTester t,
      ConsoleAnswer read, {
      ConsoleAnswer me = consoleMe,
    }) async {
      final api = await _home(
        t,
        me: me,
        answers: {'case': read},
        queue: {
          'appeal': _cases([_row('c3', kind: 'appeal')]),
        },
      );
      await t.tap(find.text('Appeals'));
      await t.pumpAndSettle();
      await _open(t, 'console_case_c3');
      return api;
    }

    testWidgets('M-3: Accept says what stays; Reject says Done', (t) async {
      final api = await appealPage(t, appeal());
      expect(await _confirmText(t, 'console_appeal_accept'), kConfirmAccept);
      await t.tap(_key('console_appeal_accept'));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(api.of('decide_appeal'), [
        {'case_id': 'c3', 'accept': true},
      ]);
      expect(
        t.widget<Text>(_key('console_case_line')).data,
        'Accepted. $kConsoleOtherHolds',
      );
      await t.tap(_key('console_appeal_reject'));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(t.widget<Text>(_key('console_case_line')).data, 'Done.');
    });

    testWidgets('M-8: the original decider and a no-decider appeal: Accept '
        'and Reject off for a moderator', (t) async {
      for (final read in [appeal(mine: true), appeal(known: false)]) {
        final api = await appealPage(t, read);
        expect(_on(t, 'console_appeal_accept'), isFalse);
        expect(_on(t, 'console_appeal_reject'), isFalse);
        await t.tap(_key('console_appeal_accept'), warnIfMissed: false);
        await t.pumpAndSettle();
        expect(api.of('decide_appeal'), isEmpty);
      }
    });

    testWidgets('M-8: the safety owner from 24 hours after it was sent, and '
        'says from when before then', (t) async {
      final soon = DateTime.now().toUtc().subtract(const Duration(hours: 2));
      await appealPage(
        t,
        appeal(known: false, sent: soon.toIso8601String()),
        me: consoleOwner,
      );
      expect(_on(t, 'console_appeal_accept'), isFalse);
      expect(
        t.widget<Text>(_key('console_appeal_blocked')).data,
        'You can decide it from '
        '${consoleDate(soon.add(const Duration(hours: 24)).toIso8601String())}.',
      );
      await appealPage(t, appeal(mine: true), me: consoleOwner);
      expect(_on(t, 'console_appeal_accept'), isTrue);
      expect(_on(t, 'console_appeal_reject'), isTrue);
      expect(_key('console_appeal_blocked'), findsNothing);
    });

    test('M-8: the rule, with its clock', () {
      const owner = ConsoleMe(role: 'safety_owner', routing: true);
      const mod = ConsoleMe(role: 'moderator', routing: false);
      final sent = {'submitted_at': '2026-11-21T10:00:00Z'};
      final at = DateTime.utc(2026, 11, 22, 9, 59);
      final after = DateTime.utc(2026, 11, 22, 10);
      expect(consoleAppealBlocked(sent, {'decided_by_me': false}, mod, at), isNull);
      expect(
        consoleAppealBlocked(sent, {'decided_by_me': true}, mod, after),
        consoleReason('same_decider'),
      );
      expect(
        consoleAppealBlocked(sent, {'decider_known': false}, mod, after),
        consoleReason('decider_unknown'),
      );
      expect(consoleAppealBlocked(sent, {'decided_by_me': true}, owner, at), isNotNull);
      expect(consoleAppealBlocked(sent, {'decided_by_me': true}, owner, after), isNull);
      expect(consoleAppealBlocked(sent, {'decider_known': false}, owner, after), isNull);
    });

    test('M-9: Accept says Dating stays paused until the person resumes it', () {
      expect(kConfirmAccept, contains('Dating stays paused until this person resumes it'));
      expect(kConfirmAccept, isNot(contains('opens again')));
    });

    testWidgets('M-10: the two Ask for ID actions have two names', (t) async {
      await _home(t, answers: {'case': _case(state: 'in_review')});
      await _open(t, 'console_case_c1');
      expect(
        find.descendant(of: _key('console_ask_id'), matching: find.text(kConsoleAskIdAgeCheck)),
        findsOneWidget,
      );
      expect(kConfirmCaseAskForId, startsWith('Ask for ID (age check):'));
      expect(kConfirmAskForId, startsWith('Ask for an ID document:'));
      expect(kConsoleAskIdDocument, isNot(kConsoleAskIdAgeCheck));
    });

    testWidgets('M-11: Restrict says what follows the type and length', (
      t,
    ) async {
      await _home(t, answers: {'case': _case(state: 'in_review')});
      await _open(t, 'console_case_c1');
      await t.ensureVisible(_key('console_restrict'));
      await t.tap(_key('console_restrict'));
      await t.pumpAndSettle();
      String line() =>
          t.widget<Text>(_key('console_restrict_consequence')).data!;
      expect(line(), consoleRestrictConsequence('suspended', 7));
      await t.tap(_key('console_restrict_days'));
      await t.pumpAndSettle();
      await t.tap(find.text('For good').last);
      await t.pumpAndSettle();
      expect(line(), consoleRestrictConsequence('suspended', null));
      expect(line(), contains('for good'));
      expect(line(), contains("can't be undone here"));
      expect(line(), contains('appeal once'));
      expect(consoleRestrictConsequence('suspended', 30), contains('30 days'));
      expect(consoleRestrictConsequence('suspended', 30), contains('stays paused'));
      expect(consoleRestrictConsequence('under_review', 7), contains("isn't told"));
    });
  });

  testWidgets('M-7: a list page whose read again is busy keeps the action\'s '
      'line and its rows', (t) async {
    final api = await _home(
      t,
      answers: {
        'photos': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'photos': [
              {'id': 'p1', 'position': 2, 'url': null},
            ],
          },
        ),
      },
    );
    await t.tap(find.text('Photos'));
    await t.pumpAndSettle();
    expect(_key('console_photo_p1'), findsOneWidget);
    api.answers['photos'] = ConsoleAnswer.busy;
    await t.tap(find.text('Approve'));
    await t.pumpAndSettle();
    await tapConfirm(t);
    expect(api.of('photo_decide'), hasLength(1));
    expect(t.widget<Text>(_key('console_list_line')).data, 'Done.');
    expect(_key('console_photo_p1'), findsOneWidget);
    expect(_key('console_retry'), findsOneWidget);
  });
}
