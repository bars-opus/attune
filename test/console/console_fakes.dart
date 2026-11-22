// Spec 2 W7b (§6.4): the console's fakes: an API that records every call
// and answers what a test sets (ok by default), the sign-in steps, and the
// console pumped as a signed-in moderator at desktop size. Fix round 1:
// the codes sent are recorded, and tapConfirm taps through a confirm step.
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeConsoleApi implements ConsoleApi {
  FakeConsoleApi(this.answers);

  final Map<String, ConsoleAnswer> answers;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<ConsoleAnswer> call(
    String action, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((action, params));
    return answers[action] ?? const ConsoleAnswer(ok: true);
  }

  List<Map<String, Object?>> of(String action) => [
    for (final c in calls)
      if (c.$1 == action) c.$2,
  ];
}

class FakeConsoleAuth implements ConsoleAuth {
  FakeConsoleAuth(this.state);

  ConsoleSession state;
  final codes = <String>[];
  final sent = <String>[];

  @override
  Future<ConsoleSession> session() async => state;

  @override
  Future<bool> sendCode(String phone) async {
    sent.add(phone);
    return phone.startsWith('+');
  }

  @override
  Future<bool> verifyCode(String phone, String code) async {
    codes.add(code);
    if (code != '123456') return false;
    state = ConsoleSession.needsTotp;
    return true;
  }

  @override
  Future<ConsoleEnrolment?> enrol() async =>
      const ConsoleEnrolment(factorId: 'f1', secret: 'JBSWY3DPEHPK3PXP');

  @override
  Future<bool> verifyTotp(String code, {String? factorId}) async {
    codes.add('$code/$factorId');
    if (code != '654321') return false;
    state = ConsoleSession.ready;
    return true;
  }

  @override
  Future<void> signOut() async => state = ConsoleSession.signedOut;
}

const consoleMe = ConsoleAnswer(
  ok: true,
  data: {'ok': true, 'role': 'moderator', 'sensitive_routing_allowed': false},
);
const consoleOwner = ConsoleAnswer(
  ok: true,
  data: {'ok': true, 'role': 'safety_owner', 'sensitive_routing_allowed': true},
);

final consoleQueue = ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'cases': [
      {
        'id': 'c1',
        'kind': 'report',
        'priority': 'P0',
        'category': 'threat_to_life',
        'state': 'open',
        'reports': 2,
        'sla_due_at':
            DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
        'mine': false,
        'claimed': false,
        'gone': false,
      },
      {
        'id': 'c2',
        'kind': 'signal',
        'priority': 'P1',
        'signal_kind': 'dragnet',
        'claimed': true,
      },
      {'id': 'c3', 'kind': 'appeal', 'priority': 'P2', 'claimed': false},
    ],
  },
);

const consoleCase = ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'case': {
      'id': 'c1',
      'kind': 'report',
      'priority': 'P0',
      'state': 'in_review',
      'mine': true,
    },
    'reports': [
      {
        'id': 'r1',
        'category': 'underage_risk',
        'priority': 'P0',
        'state': 'open',
        'details': 'She said she is in SHS.',
        'reporter_triggered': 'sexual_pressure',
        'evidence': [
          {
            'from': 'reported',
            'kind': 'text',
            'at': '2026-11-20T10:00:00Z',
            'text': 'after BECE',
          },
        ],
      },
    ],
    'profile': {
      'display_name': 'Kofi',
      'age': 31,
      'country': 'GH',
      'region': 'AA',
      'prompts': [
        {'prompt': 'perfect_sunday', 'answer': 'Church, then jollof.'},
      ],
      'photos': [],
    },
    'prior': [
      {
        'kind': 'signal',
        'state': 'closed',
        'outcome': 'no_action',
        'created_at': '2026-11-01',
      },
    ],
    'families': ['age_signal'],
    'appeal': null,
  },
);

Future<FakeConsoleApi> pumpHome(
  WidgetTester t, {
  ConsoleAnswer me = consoleMe,
  Map<String, ConsoleAnswer> answers = const {},
}) async {
  await t.pumpWidget(const SizedBox()); // a fresh console each time
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final api = FakeConsoleApi({
    'whoami': me,
    'queue': consoleQueue,
    'case': consoleCase,
    ...answers,
  });
  await t.pumpWidget(
    ConsoleApp(api: api, auth: FakeConsoleAuth(ConsoleSession.ready)),
  );
  await t.pumpAndSettle();
  return api;
}

/// Taps through an irreversible action's confirm step (fix round 1, I-1).
Future<void> tapConfirm(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('console_confirm_ok')));
  await t.pumpAndSettle();
}
