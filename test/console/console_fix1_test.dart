// Spec 2 W7b Task 7, fix round 1 (task-7-review.md): an irreversible
// decision names its consequence and waits for a confirm, Cancel focused
// and sending nothing (I-1); a queue read that hit its limit never claims
// a page is empty (I-2); Restrict defaults to the case's report category,
// or waits for a pick (I-3); sign-out leaves no phone number or TOTP key
// behind (M-1); the case is built whole, so its photos load inside their
// signed minute (M-2); the sign-in steps against a fake Auth (M-3); the
// Confirm a minor guard (M-4); a new code or another number (M-5); an
// idle console signs out (M-6).
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_fakes.dart';

ConsoleAnswer _caseOf({
  String kind = 'report',
  List<Map<String, Object?>> reports = const [],
  Map<String, Object?>? appeal,
}) => ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'case': {
      'id': 'c1',
      'kind': kind,
      'priority': 'P1',
      'state': 'in_review',
      'mine': true,
    },
    'reports': reports,
    'appeal': appeal,
  },
);

Map<String, Object?> _report(String id, String category, String priority) => {
  'id': id,
  'category': category,
  'priority': priority,
  'state': 'open',
  'created_at': '2026-11-20T10:00:00Z',
};

const _appeal = {
  'text': 'I did not.',
  'restriction': {
    'type': 'suspended',
    'category': 'harassment',
    'ends_at': null,
  },
};

Future<FakeConsoleApi> _openCase(
  WidgetTester t,
  ConsoleAnswer theCase, [
  Map<String, ConsoleAnswer> answers = const {},
]) async {
  final api = await pumpHome(t, answers: {'case': theCase, ...answers});
  await t.tap(find.byKey(const ValueKey('console_case_c1')));
  await t.pumpAndSettle();
  return api;
}

Future<void> _cancelSendsNothing(
  WidgetTester t,
  FakeConsoleApi api, {
  required Finder button,
  required String action,
  required String consequence,
}) async {
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
  expect(find.text(consequence), findsOneWidget, reason: action);
  final cancel = find.byKey(const ValueKey('console_confirm_cancel'));
  expect(
    Focus.of(t.element(find.text('Cancel'))).hasPrimaryFocus,
    isTrue,
    reason: '$action: Cancel is the default focus',
  );
  await t.tap(cancel);
  await t.pumpAndSettle();
  expect(api.of(action), isEmpty, reason: '$action: Cancel sends nothing');
  // Enter on the focused Cancel sends nothing either.
  await t.tap(button);
  await t.pumpAndSettle();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pumpAndSettle();
  expect(find.text(consequence), findsNothing, reason: action);
  expect(api.of(action), isEmpty, reason: '$action: Enter cancels');
}

void main() {
  group('I-1: every irreversible decision waits for a confirm', () {
    testWidgets('Confirm a minor and Dismiss on a case', (t) async {
      final api = await _openCase(
        t,
        _caseOf(reports: [_report('r1', 'underage_risk', 'P0')]),
      );
      await _cancelSendsNothing(
        t,
        api,
        button: find.byKey(const ValueKey('console_minor')),
        action: 'confirm_minor',
        consequence: kConfirmMinor,
      );
      await _cancelSendsNothing(
        t,
        api,
        button: find.byKey(const ValueKey('console_dismiss')),
        action: 'dismiss',
        consequence: kConfirmDismiss,
      );
      await t.tap(find.byKey(const ValueKey('console_dismiss')));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(api.of('dismiss'), [
        {'case_id': 'c1'},
      ]);
    });

    testWidgets('Accept and Reject an appeal', (t) async {
      final api = await _openCase(t, _caseOf(kind: 'appeal', appeal: _appeal));
      await _cancelSendsNothing(
        t,
        api,
        button: find.byKey(const ValueKey('console_appeal_accept')),
        action: 'decide_appeal',
        consequence: kConfirmAccept,
      );
      await _cancelSendsNothing(
        t,
        api,
        button: find.byKey(const ValueKey('console_appeal_reject')),
        action: 'decide_appeal',
        consequence: kConfirmReject,
      );
      await t.tap(find.byKey(const ValueKey('console_appeal_reject')));
      await t.pumpAndSettle();
      await tapConfirm(t);
      expect(api.of('decide_appeal'), [
        {'case_id': 'c1', 'accept': false},
      ]);
    });

    testWidgets('photo Approve and Opinions Remove', (t) async {
      final api = await pumpHome(
        t,
        answers: {
          'photos': const ConsoleAnswer(
            ok: true,
            data: {
              'ok': true,
              'photos': [
                {'id': 'p1', 'position': 2, 'reason': null, 'url': null},
              ],
            },
          ),
          'opinions_queue': const ConsoleAnswer(
            ok: true,
            data: {
              'ok': true,
              'reports': [
                {
                  'report_id': 'o1',
                  'reason': 'Spam',
                  'content_type': 'comment',
                  'content_id': 'cm1',
                  'content_removed': false,
                },
              ],
            },
          ),
        },
      );
      await t.tap(find.text('Photos'));
      await t.pumpAndSettle();
      await _cancelSendsNothing(
        t,
        api,
        button: find.text('Approve'),
        action: 'photo_decide',
        consequence: consoleConfirmApprove(2),
      );
      await t.tap(find.text('Opinions'));
      await t.pumpAndSettle();
      await _cancelSendsNothing(
        t,
        api,
        button: find.text('Remove'),
        action: 'opinions_remove',
        consequence: consoleConfirmRemove('comment'),
      );
    });

    testWidgets('Publish names the country and the parsed values', (t) async {
      final api = await pumpHome(
        t,
        me: consoleOwner,
        answers: {
          'countries': const ConsoleAnswer(
            ok: true,
            data: {'ok': true, 'countries': []},
          ),
        },
      );
      await t.tap(find.text('Countries'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('console_country_code')),
        'gh',
      );
      await t.enterText(
        find.byKey(const ValueKey('console_country_values')),
        '{"same_gender_enabled":false}',
      );
      await _cancelSendsNothing(
        t,
        api,
        button: find.byKey(const ValueKey('console_publish')),
        action: 'publish_country',
        consequence: consoleConfirmPublish('GH', {
          'same_gender_enabled': false,
        }),
      );
      expect(
        consoleConfirmPublish('GH', {'same_gender_enabled': false}),
        allOf(
          contains('GH'),
          contains('"same_gender_enabled": false'),
          contains('Turning same gender off closes'),
        ),
      );
      expect(
        consoleConfirmPublish('GH', {'dating_enabled': true}),
        isNot(contains('same gender')),
      );
    });
  });

  group('I-2: a queue read that hit its limit', () {
    ConsoleAnswer reports(int n, {bool appeal = false}) => ConsoleAnswer(
      ok: true,
      data: {
        'ok': true,
        'cases': [
          for (var i = 0; i < n; i++)
            {'id': 'r$i', 'kind': 'report', 'priority': 'P0', 'claimed': true},
          if (appeal)
            {'id': 'a1', 'kind': 'appeal', 'priority': 'P2', 'claimed': false},
        ],
      },
    );

    testWidgets('never says Nothing is waiting; says more are waiting', (
      t,
    ) async {
      await pumpHome(t, answers: {'queue': reports(kConsoleQueueLimit)});
      await t.tap(find.text('Appeals'));
      await t.pumpAndSettle();
      expect(find.text(kConsoleQueueCapped), findsOneWidget);
      expect(find.text('Nothing is waiting.'), findsNothing);
    });

    testWidgets('below the limit, an empty page is empty and nothing more '
        'is said', (t) async {
      await pumpHome(t, answers: {'queue': reports(kConsoleQueueLimit - 1)});
      await t.tap(find.text('Appeals'));
      await t.pumpAndSettle();
      expect(find.text('Nothing is waiting.'), findsOneWidget);
      expect(find.text(kConsoleQueueCapped), findsNothing);
    });

    testWidgets('the limit asked for is the limit judged; each kind is its '
        'own read (W7 final client fix, I-5)', (t) async {
      final api = await pumpHome(t);
      expect(api.of('queue'), [
        for (final kind in [
          'id_check',
          'report',
          'photo',
          'verification',
          'csam_hit',
        ])
          {'kind': kind, 'limit': kConsoleQueueLimit},
      ]);
    });
  });

  group('I-3: the Restrict category', () {
    testWidgets("defaults to the case's leading report category", (t) async {
      final api = await _openCase(
        t,
        _caseOf(
          reports: [
            _report('r1', 'spam', 'P3'),
            _report('r2', 'romance_scam', 'P1'),
          ],
        ),
      );
      await t.tap(find.byKey(const ValueKey('console_restrict')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('console_restrict_save')));
      await t.pumpAndSettle();
      expect(api.of('restrict').single['category'], 'romance_scam');
    });

    testWidgets('with no report, Restrict waits for a pick', (t) async {
      final api = await _openCase(t, _caseOf(kind: 'signal'));
      await t.tap(find.byKey(const ValueKey('console_restrict')));
      await t.pumpAndSettle();
      final save = find.byKey(const ValueKey('console_restrict_save'));
      expect(t.widget<FilledButton>(save).onPressed, isNull);
      expect(find.text('Pick a category'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('console_restrict_category')));
      await t.pumpAndSettle();
      await t.tap(find.text('spam').last);
      await t.pumpAndSettle();
      await t.tap(save);
      await t.pumpAndSettle();
      expect(api.of('restrict').single['category'], 'spam');
    });
  });

  testWidgets('M-4: Confirm a minor is offered only on an underage_risk '
      'case', (t) async {
    await _openCase(t, _caseOf(reports: [_report('r1', 'threats', 'P1')]));
    expect(find.byKey(const ValueKey('console_dismiss')), findsOneWidget);
    expect(find.byKey(const ValueKey('console_minor')), findsNothing);
  });

  testWidgets('M-2: the case is built whole (its photos load inside their '
      'signed minute)', (t) async {
    await _openCase(
      t,
      _caseOf(
        reports: [for (var i = 0; i < 30; i++) _report('r$i', 'spam', 'P3')],
      ),
    );
    expect(
      find.byKey(const ValueKey('console_add_note'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('P3 · spam · open', skipOffstage: false),
      findsNWidgets(30),
    );
  });

  testWidgets('M-2: a signed photo that will not load reads the page '
      'again once, never in a loop', (t) async {
    final api = await pumpHome(
      t,
      answers: {
        'photos': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'photos': [
              {
                'id': 'p1',
                'position': 1,
                'url': 'https://storage.example/expired.jpg',
              },
            ],
          },
        ),
      },
    );
    await t.tap(find.text('Photos'));
    await t.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(find.text("Couldn't load.\nRead again."), findsOneWidget);
    expect(api.of('photos'), hasLength(2), reason: 'one read again, no loop');
  });

  group('M-1: sign-out leaves nothing behind', () {
    testWidgets('the phone number field is empty after sign-out', (t) async {
      final auth = FakeConsoleAuth(ConsoleSession.signedOut);
      await t.pumpWidget(
        ConsoleApp(
          api: FakeConsoleApi({'whoami': consoleMe, 'queue': consoleQueue}),
          auth: auth,
        ),
      );
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
      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      final phone = t.widget<TextField>(
        find.byKey(const ValueKey('console_phone')),
      );
      expect(phone.controller!.text, isEmpty);
    });

    testWidgets('a copied TOTP key is cleared from the clipboard on '
        'sign-out and once the app has it', (t) async {
      String? clip;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
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
      Future<FakeConsoleAuth> enrolAndCopy() async {
        final auth = FakeConsoleAuth(ConsoleSession.needsEnrol);
        await t.pumpWidget(const SizedBox());
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
        expect(clip, 'JBSWY3DPEHPK3PXP');
        expect(find.text(kConsoleClipboardHint), findsOneWidget);
        return auth;
      }

      await enrolAndCopy();
      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      expect(clip, isEmpty, reason: 'cleared on sign-out');

      await enrolAndCopy();
      await t.enterText(find.byKey(const ValueKey('console_totp')), '654321');
      await t.tap(find.byKey(const ValueKey('console_verify')));
      await t.pumpAndSettle();
      expect(find.text('Moderator'), findsOneWidget);
      expect(clip, isEmpty, reason: 'cleared once the app has the key');

      // Spec 2 W7c Task 9 (the re-review's N-1): the clipboard is never
      // read (a read can raise the browser's permission prompt), so once
      // this console copied the key it empties the clipboard whatever it
      // now holds; the hint says so.
      await enrolAndCopy();
      clip = 'something else the moderator copied';
      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      expect(clip, isEmpty, reason: 'emptied without being read');
    });
  });

  testWidgets('M-5: a new code, or another number', (t) async {
    final auth = FakeConsoleAuth(ConsoleSession.signedOut);
    await t.pumpWidget(ConsoleApp(api: FakeConsoleApi({}), auth: auth));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('console_phone')),
      '+233244000000',
    );
    await t.tap(find.byKey(const ValueKey('console_next')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_resend')));
    await t.pumpAndSettle();
    expect(auth.sent, ['+233244000000', '+233244000000']);
    expect(find.text('We sent a new code.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('console_change_number')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('console_code')), findsNothing);
    expect(find.text('Send code'), findsOneWidget);
  });

  group('M-6: an idle console signs out', () {
    testWidgets('after 30 minutes without activity, with a line', (t) async {
      await pumpHome(t);
      await t.tap(find.byKey(const ValueKey('console_case_c1')));
      await t.pumpAndSettle();
      await t.pump(kConsoleIdle + const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console_phone')), findsOneWidget);
      expect(find.text(kConsoleIdleLine), findsOneWidget);
    });

    testWidgets('activity keeps the moderator signed in', (t) async {
      await pumpHome(t);
      await t.pump(kConsoleIdle - const Duration(minutes: 1));
      await t.tap(find.text('Appeals'));
      await t.pump(kConsoleIdle - const Duration(minutes: 1));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump(kConsoleIdle - const Duration(minutes: 1));
      await t.pumpAndSettle();
      expect(find.text('Moderator'), findsOneWidget);
    });
  });
}
