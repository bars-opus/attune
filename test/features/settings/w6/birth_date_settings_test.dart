// Spec 1 W6b (§3.15): Settings -> Date of birth. "Your age: {age}", never
// the date; "Fix a mistake" once while the server says it is open, through
// A2 again; under 18 is X1 with the phone blocked and the account signed
// out; otherwise "To change this, contact support."
//   flutter test --update-goldens test/features/settings/w6/birth_date_settings_test.dart
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart'
    show catchUpSignOutProvider;
import 'package:attune/features/settings/data/birth_date_settings_service.dart';
import 'package:attune/features/settings/presentation/screens/birth_date_settings_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart' show FakeHomeAuth, testUser;

class _Server {
  Map<String, dynamic> status = {
    'age': 30,
    'can_correct': true,
    'correct_until': '2026-11-08T10:00:00Z',
  };
  Object? correction = {'status': 'ok', 'age': 31, 'changed': true};
  final calls = <(String, Map<String, dynamic>?)>[];
  int signOuts = 0;
  bool statusFails = false;

  Future<Object?> rpc(String fn, Map<String, dynamic>? params) async {
    calls.add((fn, params));
    if (fn == 'get_my_birth_date_status') {
      if (statusFails) throw Exception('offline');
      return status;
    }
    final answer = correction;
    if (answer is Exception) throw answer;
    return answer;
  }

  List<Override> get overrides => [
    birthDateSettingsServiceProvider.overrideWithValue(
      BirthDateSettingsService(rpc),
    ),
    catchUpSignOutProvider.overrideWithValue(() async => signOuts++),
  ];
}

Future<FlowHarness> _pump(WidgetTester tester, _Server server) =>
    pumpFlowScreen(
      tester,
      () => const BirthDateSettingsScreen(),
      overrides: server.overrides,
    );

Future<void> _fix(WidgetTester tester, String year) async {
  await tester.tap(find.text('Fix a mistake'));
  await tester.pumpAndSettle();
  expect(find.text('Fix your date of birth'), findsOneWidget);
  await tester.enterText(find.bySemanticsLabel('Day of birth'), '2');
  await tester.enterText(find.bySemanticsLabel('Month of birth'), '6');
  await tester.enterText(find.bySemanticsLabel('Year of birth'), year);
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

/// What the screen announced to screen readers (iOS reads no live region).
List<String> _announcements(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  final said = <String>[];
  messenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final event = message as Map<Object?, Object?>;
      if (event['type'] == 'announce') {
        said.add((event['data'] as Map<Object?, Object?>)['message'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      null,
    ),
  );
  return said;
}

void main() {
  testWidgets('the age, never the date, and the one fix while it is open', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);
    expect(find.text('Your age: 30'), findsOneWidget);
    final until = MyDateFormat.toDate(
      DateTime.parse('2026-11-08T10:00:00Z').toLocal(),
    );
    expect(
      find.text("If it's wrong, you can fix it once, until $until."),
      findsOneWidget,
    );
    server.status = {'age': 31, 'can_correct': false, 'correct_until': null};
    await _fix(tester, '1995');
    expect(
      server.calls.where((c) => c.$1 == 'correct_my_birth_date').single.$2,
      {'p_birth_date': '1995-06-02'},
    );
    expect(find.text('Saved.'), findsOneWidget);
    expect(find.text('Your age: 31'), findsOneWidget);
    expect(find.text('To change this, contact support.'), findsOneWidget);
    expect(find.text('Fix a mistake'), findsNothing);
    expect(
      find.textContaining('1995'),
      findsNothing,
      reason: 'the date is never shown',
    );
  });

  testWidgets('closed: contact support, no fix', (tester) async {
    final server =
        _Server()
          ..status = {'age': 30, 'can_correct': false, 'correct_until': null};
    await _pump(tester, server);
    expect(find.text('To change this, contact support.'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text('Fix a mistake'), findsNothing);
  });

  // Carried rule (batch 7): the "until" date only while the fix is open,
  // whatever a status row carries.
  testWidgets('closed with a stray until: no date, contact support', (
    tester,
  ) async {
    final server =
        _Server()
          ..status = {
            'age': 30,
            'can_correct': false,
            'correct_until': '2026-11-08T10:00:00Z',
          };
    await _pump(tester, server);
    expect(find.textContaining('until'), findsNothing);
    expect(find.text('To change this, contact support.'), findsOneWidget);
  });

  testWidgets(
    'closed since the screen opened: back to the status, which says so',
    (tester) async {
      final server =
          _Server()
            ..correction = const PostgrestException(
              message: 'birth_date:correction_closed',
              code: 'P0001',
            );
      await _pump(tester, server);
      server.status = {'age': 30, 'can_correct': false, 'correct_until': null};
      await _fix(tester, '1995');
      expect(find.text('To change this, contact support.'), findsOneWidget);
    },
  );

  testWidgets('a correction to under 18: blocked, signed out, X1', (
    tester,
  ) async {
    final server = _Server()..correction = {'status': 'not_eligible'};
    final h = await _pump(tester, server);
    await _fix(tester, '2012');
    expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
    expect(h.routing.underAgeBlocked, isTrue);
    expect(server.signOuts, 1);
    expect(h.location, '/age-stop?from=account');
  });

  // Carried rule (batch 7): the gate's order, block -> clear -> sign out:
  // what this account left queued on the phone goes before the sign-out,
  // and a sign-out that throws still ends at X1.
  testWidgets(
    'under 18: the queue is cleared, and a failed sign-out still ends at X1',
    (tester) async {
      final server = _Server()..correction = {'status': 'not_eligible'};
      final order = <String>[];
      final h = await pumpFlowScreen(
        tester,
        () => const BirthDateSettingsScreen(),
        prefsValues: {
          OnboardingStore.pendingInviteCodeKey: 'ABC123',
          'attune.onboarding.user.u1.pending_path': 'couple',
        },
        overrides: [
          ...server.overrides,
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u1'))),
          catchUpSignOutProvider.overrideWithValue(() async {
            final prefs = await SharedPreferences.getInstance();
            order.add(
              'signOut blocked=${AgeGateStore.readBlocked(prefs, DateTime.now())} '
              'invite=${prefs.getString(OnboardingStore.pendingInviteCodeKey)} '
              'path=${prefs.getString('attune.onboarding.user.u1.pending_path')}',
            );
            throw Exception('offline');
          }),
        ],
      );
      await _fix(tester, '2012');
      expect(order, ['signOut blocked=true invite=null path=null']);
      expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
      expect(h.location, '/age-stop?from=account');
    },
  );

  // Batch 7 review I-1: the not_eligible answer was lost, the retry with
  // the same date comes back 'ok' with an age under 18. Still X1.
  testWidgets('a lost under-18 answer retried: ok under 18 is still X1', (
    tester,
  ) async {
    final server =
        _Server()..correction = {'status': 'ok', 'age': 15, 'changed': false};
    final h = await _pump(tester, server);
    await _fix(tester, '2012');
    expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
    expect(h.routing.underAgeBlocked, isTrue);
    expect(server.signOuts, 1);
    expect(h.location, '/age-stop?from=account');
    expect(find.text('Saved.'), findsNothing);
  });

  // Batch 7 review I-1: an account the server says is under 18 (only ever
  // a held one) never stays on the status, signed in.
  testWidgets('a status under 18: blocked, signed out, X1, once', (
    tester,
  ) async {
    final server =
        _Server()
          ..status = {'age': 15, 'can_correct': false, 'correct_until': null};
    final h = await _pump(tester, server);
    expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
    expect(h.routing.underAgeBlocked, isTrue);
    expect(server.signOuts, 1);
    expect(h.location, '/age-stop?from=account');
  });

  // Batch 7 review M-1, M-2: what changes without a tap is said aloud.
  testWidgets('a failed load is announced, and so is a closed bounce', (
    tester,
  ) async {
    final failing = _Server()..statusFails = true;
    final said = _announcements(tester);
    await _pump(tester, failing);
    const loadFailed =
        "We couldn't load this. Check your connection and try again.";
    expect(find.text(loadFailed), findsOneWidget);
    expect(said, [loadFailed]);

    final closing =
        _Server()
          ..correction = const PostgrestException(
            message: 'birth_date:correction_closed',
            code: 'P0001',
          );
    await _pump(tester, closing);
    said.clear();
    closing.status = {'age': 30, 'can_correct': false, 'correct_until': null};
    await _fix(tester, '1995');
    expect(said, ['To change this, contact support.']);
  });

  // Batch 7 review M-3: the line and the button agree without a date.
  testWidgets('open with no until: the text and the button agree', (
    tester,
  ) async {
    final server =
        _Server()
          ..status = {'age': 30, 'can_correct': true, 'correct_until': null};
    await _pump(tester, server);
    expect(find.text('To change this, contact support.'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text('Fix a mistake'), findsNothing);
  });

  testWidgets('a failed save stays on A2 and says so', (tester) async {
    final server = _Server()..correction = Exception('offline');
    await _pump(tester, server);
    await _fix(tester, '1995');
    expect(find.text('Fix your date of birth'), findsOneWidget);
    expect(find.text("We couldn't save that. Try again."), findsOneWidget);
  });

  testWidgets('the Settings row only under flow_signin_v2', (tester) async {
    for (final on in [true, false]) {
      await pumpFlowScreen(
        tester,
        () => Consumer(
          builder:
              (context, ref, _) =>
                  Text(birthDateSetting(context, ref)?.title ?? 'no row'),
        ),
        overrides: [flowSignInV2Provider.overrideWithValue(on)],
      );
      expect(find.text(on ? 'Date of birth' : 'no row'), findsOneWidget);
    }
  });

  testWidgets('guidelines, and goldens open and closed', (tester) async {
    await _pump(tester, _Server());
    await expectFlowGuidelines(tester);
    await expectFlowGoldens(
      tester,
      'dob_settings_open',
      () => const BirthDateSettingsScreen(),
      overrides: _Server().overrides,
    );
    final closed =
        _Server()
          ..status = {'age': 30, 'can_correct': false, 'correct_until': null};
    await expectFlowGoldens(
      tester,
      'dob_settings_closed',
      () => const BirthDateSettingsScreen(),
      overrides: closed.overrides,
    );
  });
}
