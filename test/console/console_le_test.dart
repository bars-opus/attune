// Spec 2 W7c Task 9 (§6.4, §6.5, §6.6): the law-enforcement page is the
// safety owner's (a moderator's console asks nothing); a request is
// recorded, then decided with what was disclosed and whether the person
// was told; the transparency summary for a window; a case records an
// escalation (CSA 292 only as the consent kind), one request.
import 'package:attune/console/console_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_fakes.dart';

void main() {
  testWidgets('a moderator\'s console asks nothing of the log', (t) async {
    final api = await pumpHome(t);
    await t.tap(find.text('Law enforcement'));
    await t.pumpAndSettle();
    expect(
      find.text('The law-enforcement log is the safety owner\'s.'),
      findsOneWidget,
    );
    expect(api.of('le_requests'), isEmpty);
  });

  testWidgets('the owner records a request, decides it, and counts a quarter', (
    t,
  ) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'le_requests': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'requests': [
              {
                'id': 'l1',
                'jurisdiction': 'GH',
                'decision': 'pending',
                'received_at': '2026-11-20',
                'legal_basis': 'Court order',
                'scope': 'One account',
              },
            ],
          },
        ),
        'transparency': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'summary': {'requests_met': 2},
          },
        ),
      },
    );
    await t.tap(find.text('Law enforcement'));
    await t.pumpAndSettle();
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
    await t.tap(find.byKey(const ValueKey('console_le_record')));
    await t.pumpAndSettle();
    final recorded = api.of('le_record').single;
    final values = recorded['values']! as Map<String, Object?>;
    expect(values['jurisdiction'], 'GH');
    expect(values['legal_basis'], 'Court order');
    expect(values.containsKey('received_at'), isTrue);
    expect(recorded.containsKey('request_id'), isFalse);
    await t.tap(find.text('Decide'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_le_decision')));
    await t.pumpAndSettle();
    await t.tap(find.text('Partly disclosed').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_le_disclosed_account')));
    await t.tap(find.byKey(const ValueKey('console_le_told')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_le_decide_save')));
    await t.pumpAndSettle();
    expect(api.of('le_record').last, {
      'request_id': 'l1',
      'values': {
        'decision': 'partly_disclosed',
        'disclosed_categories': ['account'],
        'user_notified': true,
      },
    });
    await t.ensureVisible(find.byKey(const ValueKey('console_le_from')));
    await t.enterText(
      find.byKey(const ValueKey('console_le_from')),
      '2026-07-01',
    );
    await t.enterText(
      find.byKey(const ValueKey('console_le_to')),
      '2026-10-01',
    );
    await t.ensureVisible(find.byKey(const ValueKey('console_le_summary')));
    await t.tap(find.byKey(const ValueKey('console_le_summary')));
    await t.pumpAndSettle();
    expect(api.of('transparency'), [
      {'from': '2026-07-01', 'to': '2026-10-01'},
    ]);
    expect(find.textContaining('"requests_met": 2'), findsOneWidget);
  });

  testWidgets('a case records an escalation: its kind and their reference', (
    t,
  ) async {
    final api = await pumpHome(t);
    await t.tap(find.byKey(const ValueKey('console_case_c1')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('console_escalate')));
    await t.tap(find.byKey(const ValueKey('console_escalate')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_escalation_kind')));
    await t.pumpAndSettle();
    await t.tap(find.text("CSA 292, with the person's consent").last);
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('console_escalation_reference')),
      ' CSA-2026-0001 ',
    );
    await t.tap(find.byKey(const ValueKey('console_escalation_save')));
    await t.pumpAndSettle();
    expect(api.of('escalate'), [
      {
        'case_id': 'c1',
        'kind': 'csa_292_with_consent',
        'reference': 'CSA-2026-0001',
      },
    ]);
  });
}
