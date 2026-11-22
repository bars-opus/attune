// Spec 2 W7b Task 7 (§6.4; F-6): the moderation console. Sign-in is the
// phone's code, then TOTP (a first sign-in enrols), then the server's
// moderator check; the queue lists the server's cases by page, claims and
// opens them; a case shows its reports (text, credibility, evidence), the
// person as others see them, the families, earlier cases and an appeal,
// and each action sends one request with the case's id; a refused case
// reads as unavailable; photos, verifications, Opinions, countries (the
// owner publishes) and the audit. The console imports only lib/console,
// Flutter and the Supabase client, and nothing else imports it.
import 'dart:io';

import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_fakes.dart';

void main() {
  testWidgets('sign-in: the code, then TOTP, then the moderator check', (
    t,
  ) async {
    final api = FakeConsoleApi({'whoami': consoleMe, 'queue': consoleQueue});
    final auth = FakeConsoleAuth(ConsoleSession.signedOut);
    await t.pumpWidget(ConsoleApp(api: api, auth: auth));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('console_phone')),
      '+233244000000',
    );
    await t.tap(find.byKey(const ValueKey('console_next')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('console_code')), '000000');
    await t.tap(find.byKey(const ValueKey('console_next')));
    await t.pumpAndSettle();
    expect(find.text("That code didn't work."), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('console_code')), '123456');
    await t.tap(find.byKey(const ValueKey('console_next')));
    await t.pumpAndSettle();
    expect(
      find.text('Enter the code from your authenticator app.'),
      findsOneWidget,
    );
    expect(api.of('whoami'), isEmpty, reason: 'nothing is asked before aal2');
    await t.enterText(find.byKey(const ValueKey('console_totp')), '654321');
    await t.tap(find.byKey(const ValueKey('console_verify')));
    await t.pumpAndSettle();
    expect(api.of('whoami'), hasLength(1));
    expect(find.text('Moderator'), findsOneWidget);
    expect(find.byKey(const ValueKey('console_case_c1')), findsOneWidget);
  });

  testWidgets('a first sign-in enrols an authenticator app; someone who is '
      'not a moderator stays out', (t) async {
    final api = FakeConsoleApi({
      'whoami': const ConsoleAnswer(ok: false, reason: 'not_moderator'),
    });
    final auth = FakeConsoleAuth(ConsoleSession.needsEnrol);
    await t.pumpWidget(ConsoleApp(api: api, auth: auth));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_enrol')));
    await t.pumpAndSettle();
    expect(find.text('Key: JBSWY3DPEHPK3PXP'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('console_totp')), '654321');
    await t.tap(find.byKey(const ValueKey('console_verify')));
    await t.pumpAndSettle();
    expect(auth.codes.last, '654321/f1');
    expect(find.text("This account isn't a moderator."), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('the queue by page: claim sends the case\'s id and reads '
      'again; appeals and signals have their own pages', (t) async {
    final api = await pumpHome(t);
    expect(find.text('P0 · report · threat_to_life'), findsOneWidget);
    expect(find.textContaining('2 reports'), findsOneWidget);
    expect(find.byKey(const ValueKey('console_case_c2')), findsNothing);
    expect(find.byKey(const ValueKey('console_case_c3')), findsNothing);
    await t.tap(find.text('Claim'));
    await t.pumpAndSettle();
    expect(api.of('claim'), [
      {'case_id': 'c1'},
    ]);
    // W7 final client fix (I-5): each load reads every kind of the page.
    expect(api.of('queue').where((q) => q['kind'] == 'report'), hasLength(2));
    await t.tap(find.text('Appeals'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('console_case_c3')), findsOneWidget);
    await t.tap(find.text('Signals'));
    await t.pumpAndSettle();
    expect(find.text('P1 · signal · dragnet'), findsOneWidget);
  });

  testWidgets('a case: its reports, the credibility note, the evidence, the '
      'person, the families and earlier cases; each action is one request', (
    t,
  ) async {
    final api = await pumpHome(t);
    await t.tap(find.byKey(const ValueKey('console_case_c1')));
    await t.pumpAndSettle();
    expect(find.text('"She said she is in SHS."'), findsOneWidget);
    expect(
      find.text(
        "The reporter's messages in this chat triggered: sexual_pressure",
      ),
      findsOneWidget,
    );
    expect(find.text('Evidence (1 messages)'), findsOneWidget);
    expect(find.text('Kofi · 31 · GH · AA'), findsOneWidget);
    expect(find.text('perfect_sunday: Church, then jollof.'), findsOneWidget);
    expect(find.text('age_signal'), findsOneWidget);
    expect(find.textContaining('no_action'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('console_hold')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_category_underage_risk')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_restrict')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_restrict_save')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('console_minor')));
    await t.tap(find.byKey(const ValueKey('console_minor')));
    await t.pumpAndSettle();
    await tapConfirm(t);
    await t.ensureVisible(find.byKey(const ValueKey('console_add_note')));
    await t.tap(find.byKey(const ValueKey('console_add_note')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('console_note')), 'Checked.');
    await t.tap(find.byKey(const ValueKey('console_note_save')));
    await t.pumpAndSettle();
    expect(api.of('hold'), [
      {'case_id': 'c1', 'category': 'underage_risk'},
    ]);
    final restrict = api.of('restrict').single;
    expect(restrict['type'], 'suspended');
    expect(
      restrict['category'],
      'underage_risk',
      reason: "fix round 1 (I-3): the case's report category, never harassment",
    );
    final ends = DateTime.parse(restrict['ends_at']! as String);
    expect(ends.difference(DateTime.now()).inDays, inInclusiveRange(6, 7));
    expect(api.of('confirm_minor'), [
      {'case_id': 'c1'},
    ]);
    expect(api.of('note'), [
      {'case_id': 'c1', 'note': 'Checked.'},
    ]);
    expect(api.of('case').length, 5, reason: 'read again after each action');
  });

  testWidgets('a refused case reads as unavailable; an appeal decided by '
      'its decider says so', (t) async {
    final api = await pumpHome(
      t,
      answers: {
        'case': const ConsoleAnswer(ok: false, reason: 'case_unavailable'),
      },
    );
    await t.tap(find.byKey(const ValueKey('console_case_c1')));
    await t.pumpAndSettle();
    expect(find.text("This case isn't available."), findsOneWidget);
    api.answers['case'] = const ConsoleAnswer(
      ok: true,
      data: {
        'ok': true,
        'case': {
          'id': 'c3',
          'kind': 'appeal',
          'priority': 'P2',
          'state': 'open',
        },
        'reports': [],
        'appeal': {
          'text': 'I did not.',
          'restriction': {
            'type': 'suspended',
            'category': 'harassment',
            'ends_at': null,
          },
        },
      },
    );
    api.answers['decide_appeal'] = const ConsoleAnswer(
      ok: false,
      reason: 'same_decider',
    );
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Appeals'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_case_c3')));
    await t.pumpAndSettle();
    expect(find.text('"I did not."'), findsOneWidget);
    expect(
      find.text('Restriction: suspended · harassment · until closed for good'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('console_dismiss')), findsNothing);
    await t.tap(find.byKey(const ValueKey('console_appeal_accept')));
    await t.pumpAndSettle();
    await tapConfirm(t);
    expect(api.of('decide_appeal'), [
      {'case_id': 'c3', 'accept': true},
    ]);
    expect(
      find.text(
        'A different person from the one who made the decision must decide this appeal.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('photos, verifications, Opinions and the audit', (t) async {
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
                'position': 3,
                'reason': 'needs_review',
                'url': null,
              },
            ],
          },
        ),
        'verifications': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'sessions': [
              {
                'id': 's1',
                'step': 'human',
                'kind': 'activation',
                'gestures': ['smile', 'left'],
                'review': [],
                'photos': [],
              },
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
                'reason': 'Someone may be at risk',
                'excerpt': 'I cannot go on',
                'content_type': 'opinion',
                'content_id': 'op1',
                'content_removed': false,
              },
            ],
          },
        ),
        'audit': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'actions': [
              {
                'action': 'claim',
                'mine': true,
                'at': '2026-11-21T10:00:00Z',
                'detail': {},
              },
            ],
          },
        ),
      },
    );
    await t.tap(find.text('Photos'));
    await t.pumpAndSettle();
    await t.tap(find.text('Approve'));
    await t.pumpAndSettle();
    await tapConfirm(t);
    await t.tap(find.byKey(const ValueKey('console_photo_reject_p1')));
    await t.pumpAndSettle();
    await t.tap(find.text('face_unclear').last);
    await t.pumpAndSettle();
    expect(api.of('photo_decide'), [
      {'photo_id': 'p1', 'approve': true},
      {'photo_id': 'p1', 'approve': false, 'reason': 'face_unclear'},
    ]);
    await t.tap(find.text('Verifications'));
    await t.pumpAndSettle();
    expect(find.text('Gestures: smile, left'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('console_pass_s1')));
    await t.pumpAndSettle();
    await tapConfirm(t);
    expect(api.of('verification_decide'), [
      {'session_id': 's1', 'outcome': 'pass'},
    ]);
    await t.tap(find.text('Opinions'));
    await t.pumpAndSettle();
    expect(find.textContaining('keep the post or escalate it'), findsOneWidget);
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    await tapConfirm(t);
    expect(api.of('opinions_remove'), [
      {'type': 'opinion', 'id': 'op1'},
    ]);
    await t.tap(find.text('Audit'));
    await t.pumpAndSettle();
    expect(find.text('claim (you)'), findsOneWidget);
  });

  testWidgets('countries: a moderator reads; only the safety owner publishes', (
    t,
  ) async {
    const countries = ConsoleAnswer(
      ok: true,
      data: {
        'ok': true,
        'countries': [
          {
            'country': 'GH',
            'tier': 1,
            'version': 3,
            'dating_enabled': false,
            'same_gender_enabled': false,
          },
        ],
      },
    );
    await pumpHome(t, answers: {'countries': countries});
    await t.tap(find.text('Countries'));
    await t.pumpAndSettle();
    expect(find.text('GH · tier 1 · v3'), findsOneWidget);
    expect(find.byKey(const ValueKey('console_publish')), findsNothing);
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {'countries': countries},
    );
    await t.tap(find.text('Countries'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('console_country_code')), 'gh');
    await t.enterText(
      find.byKey(const ValueKey('console_country_values')),
      '{"dating_enabled": true}',
    );
    await t.tap(find.byKey(const ValueKey('console_publish')));
    await t.pumpAndSettle();
    await tapConfirm(t);
    expect(api.of('publish_country'), [
      {
        'country': 'GH',
        'values': {'dating_enabled': true},
      },
    ]);
  });

  test('the console imports only lib/console, Flutter and the Supabase '
      'client; nothing else imports the console', () {
    final allowed = RegExp(
      r"^import '(dart:[a-z_]+|package:flutter/[a-z_]+\.dart|package:supabase_flutter/supabase_flutter\.dart|package:attune/console/[a-z_/]+\.dart)'",
    );
    for (final f
        in Directory(
          'lib/console',
        ).listSync(recursive: true).whereType<File>()) {
      for (final line in f.readAsLinesSync().where(
        (l) => l.startsWith('import '),
      )) {
        expect(allowed.hasMatch(line), isTrue, reason: '${f.path}: $line');
      }
    }
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (f.path.startsWith('lib/console/') || !f.path.endsWith('.dart')) {
        continue;
      }
      expect(
        f.readAsStringSync().contains('package:attune/console/'),
        isFalse,
        reason: f.path,
      );
    }
  });
}
