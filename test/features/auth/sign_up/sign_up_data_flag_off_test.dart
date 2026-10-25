// Spec 1 W2b, batch 3 extras to Task 6: the shared files Task 6 edits keep
// today's behaviour with flow_signin_v2 off (EULA v1 through the real
// service and its RPCs, no account call without a queued A5), the replay
// runs before today's submission, and a known name with an accepted invite
// still goes straight to the joined step. The last group pins the batch 3
// review's fix round 1 (M-2, M-3, M-4, M-5, M-7).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/auth/data/eula_acceptance_service.dart';
import 'package:attune/features/auth/presentation/eula_gate.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/fake_account_gateway.dart';

const _me = '5f1a0000-0000-0000-0000-0000000000bb';

String _fakeJwt() {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
      1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _me, 'exp': exp, 'role': 'authenticated'})}.sig';
}

/// A signed-in client whose get_eula_acceptance answers [stored].
Future<(SupabaseClient, List<http.Request>)> _client(String? stored) async {
  final requests = <http.Request>[];
  final client = SupabaseClient(
    'http://localhost:54321',
    'test-anon-key',
    httpClient: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/rest/v1/rpc/get_eula_acceptance') {
        return http.Response(
          jsonEncode(stored),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/rest/v1/rpc/record_eula_acceptance') {
        return http.Response('', 204, request: request);
      }
      return http.Response('not found', 404, request: request);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final exp = DateTime.now().add(const Duration(days: 1));
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': _fakeJwt(),
      'token_type': 'bearer',
      'expires_in': 86400,
      'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
      'refresh_token': 'refresh',
      'user': {
        'id': _me,
        'aud': 'authenticated',
        'phone': '233241234567',
        'app_metadata': <String, Object>{},
        'user_metadata': <String, Object>{},
        'created_at': '2026-07-01T00:00:00Z',
      },
    }),
  );
  return (client, requests);
}

List<String> _rpcs(List<http.Request> requests) => [
  for (final r in requests)
    if (r.url.path.startsWith('/rest/v1/rpc/'))
      r.url.path.substring('/rest/v1/rpc/'.length),
];

class _Submission implements OnboardingSubmissionService {
  _Submission(this.onSubmit);

  final void Function() onSubmit;
  int calls = 0;

  @override
  Future<void> submit({
    required OnboardingMode mode,
    required String displayName,
    required List<int> attachmentAnswers,
    required List<String> anchors,
  }) async {
    calls++;
    onSubmit();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late OnboardingStore store;

  const submission = PendingOnboardingSubmission(
    mode: OnboardingMode.personal,
    displayName: 'Ama',
    attachmentAnswers: [1, 2],
    anchors: ['time'],
  );
  final pending = PendingSignUp(
    displayName: 'Ama',
    birthDate: DateTime.utc(1990, 1, 2),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = OnboardingStore(
      prefs,
      scope: '${OnboardingStore.userScopePrefix}.$_me',
    );
  });

  group('EULA with flow_signin_v2 off: version 1, as today', () {
    test('a v1 account passes; no version asks; the server is read', () async {
      final (v1, v1Requests) = await _client('1');
      addTearDown(v1.dispose);
      expect(
        await EulaAcceptanceService(client: v1).needsAcceptance(),
        isFalse,
      );
      expect(_rpcs(v1Requests), ['get_eula_acceptance']);

      final (none, _) = await _client(null);
      addTearDown(none.dispose);
      expect(
        await EulaAcceptanceService(client: none).needsAcceptance(),
        isTrue,
      );
    });

    test('records version 1', () async {
      final (client, requests) = await _client(null);
      addTearDown(client.dispose);
      await EulaAcceptanceService(client: client).recordAcceptance();
      final record = requests.singleWhere(
        (r) => r.url.path == '/rest/v1/rpc/record_eula_acceptance',
      );
      expect(jsonDecode(record.body), {'p_version': '1'});
    });
  });

  group('EULA with flow_signin_v2 on: version 2', () {
    test('a v1 account is asked once more and records 2', () async {
      final (client, requests) = await _client('1');
      addTearDown(client.dispose);
      final service = EulaAcceptanceService(
        client: client,
        version: EulaAcceptanceService.v2Version,
      );
      expect(await service.needsAcceptance(), isTrue);
      await service.recordAcceptance();
      final record = requests.singleWhere(
        (r) => r.url.path == '/rest/v1/rpc/record_eula_acceptance',
      );
      expect(jsonDecode(record.body), {'p_version': '2'});
    });

    test('a queued A5 is consent already given: nothing is read', () async {
      final (client, requests) = await _client(null);
      addTearDown(client.dispose);
      await store.savePendingSignUp(pending);
      expect(
        await EulaAcceptanceService(
          client: client,
          version: EulaAcceptanceService.v2Version,
        ).needsAcceptance(),
        isFalse,
      );
      expect(_rpcs(requests), isEmpty);
    });

    test("another account's queued A5 is not this account's consent", () async {
      final (client, _) = await _client(null);
      addTearDown(client.dispose);
      await OnboardingStore(
        prefs,
        scope: '${OnboardingStore.userScopePrefix}.someone-else',
      ).savePendingSignUp(pending);
      expect(
        await EulaAcceptanceService(
          client: client,
          version: EulaAcceptanceService.v2Version,
        ).needsAcceptance(),
        isTrue,
      );
    });
  });

  group('the replay', () {
    test(
      'with no queued A5 no account call is made; today\'s replay runs',
      () async {
        final gateway = FakeAccountGateway();
        final today = _Submission(() {});
        await store.savePendingSubmission(submission);
        await OnboardingSyncService(
          submissionService: today,
          accountService: AccountService(gateway),
        ).flush(store);
        expect(gateway.calls, isEmpty);
        expect(today.calls, 1);
        expect(store.pendingSubmission, isNull);
      },
    );

    test('the account lands before today\'s onboarding submission', () async {
      final gateway = FakeAccountGateway();
      final seenAtSubmit = <int>[];
      final today = _Submission(
        () => seenAtSubmit.add(gateway.count('complete_sign_up')),
      );
      await store.savePendingSignUp(pending);
      await store.savePendingSubmission(submission);
      await OnboardingSyncService(
        submissionService: today,
        accountService: AccountService(gateway),
      ).flush(store);
      expect(seenAtSubmit, [1]);
      expect(gateway.calls.single.$2, {
        'p_display_name': 'Ama',
        'p_birth_date': '1990-01-02',
        'p_eula_version': '2',
      });
    });

    test(
      'a refusal other than age drops it without the under-18 stop',
      () async {
        final gateway =
            FakeAccountGateway()
              ..failWith = FakeAccountGateway.refusal('signup:phone_required');
        var stopped = 0;
        await store.savePendingSignUp(pending);
        await OnboardingSyncService(
          submissionService: _Submission(() {}),
          accountService: AccountService(gateway),
          onSignUpNotEligible: () async => stopped++,
        ).flush(store);
        expect(store.pendingSignUp, isNull);
        expect(stopped, 0);
      },
    );

    test('a corrupt queued A5 reads as none', () async {
      await prefs.setString(
        'attune.onboarding.${OnboardingStore.userScopePrefix}.$_me.pending_sign_up',
        '{not json',
      );
      expect(store.pendingSignUp, isNull);
    });
  });

  testWidgets(
    'a known name with an accepted invite goes straight to the joined step',
    (tester) async {
      await store.rememberDisplayName('Ɛsi');
      await tester.pumpWidget(
        ProviderScope(
          child: ScreenUtilInit(
            designSize: const Size(375, 812),
            builder:
                (_, __) => MaterialApp(
                  home: OnboardingFlow(
                    store: store,
                    acceptedPendingInvite: true,
                    onComplete: () {},
                  ),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('What should Attune call you?'), findsNothing);
      expect(find.text('Are you single or in a relationship?'), findsNothing);
      expect(find.text('You are connected'), findsOneWidget);
    },
  );

  group('review fix round 1', () {
    test(
      'M-2: the queued date of birth is the date given, in any zone',
      () async {
        await store.savePendingSignUp(
          PendingSignUp(displayName: 'Ama', birthDate: DateTime(1990, 1, 2)),
        );
        final raw =
            jsonDecode(
                  prefs.getString(
                    'attune.onboarding.${OnboardingStore.userScopePrefix}.$_me.pending_sign_up',
                  )!,
                )
                as Map;
        expect(raw['birth_date'], '1990-01-02');
        expect(store.pendingSignUp!.birthDate, DateTime.utc(1990, 1, 2));
      },
    );

    test("M-3: while A5 is still owed, today's submission waits", () async {
      final gateway =
          FakeAccountGateway()..failWith = TimeoutException('offline');
      final today = _Submission(() {});
      await store.savePendingSignUp(pending);
      await store.savePendingSubmission(submission);
      await OnboardingSyncService(
        submissionService: today,
        accountService: AccountService(gateway),
      ).flush(store);
      expect(today.calls, 0);
      expect(store.pendingSignUp, isNotNull);
      expect(store.pendingSubmission, isNotNull);
    });

    test(
      'M-3: an under-18 refusal leaves nothing the person entered',
      () async {
        final gateway =
            FakeAccountGateway()
              ..failWith = FakeAccountGateway.refusal('signup:not_eligible');
        final today = _Submission(() {});
        var stopped = 0;
        await store.complete(mode: OnboardingMode.personal, displayName: 'Ama');
        await store.savePendingSignUp(pending);
        await store.savePendingSubmission(submission);
        await OnboardingSyncService(
          submissionService: today,
          accountService: AccountService(gateway),
          onSignUpNotEligible: () async => stopped++,
        ).flush(store);
        expect(today.calls, 0);
        expect(stopped, 1);
        expect(store.displayName, isNull);
        expect(store.mode, isNull);
        expect(store.isComplete, isFalse);
        expect(store.pendingSubmission, isNull);
        expect(store.pendingSignUp, isNull);
      },
    );

    test('M-4: the default stop blocks this phone with no Supabase', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final gateway =
          FakeAccountGateway()
            ..failWith = FakeAccountGateway.refusal('signup:not_eligible');
      await store.savePendingSignUp(pending);
      await expectLater(
        OnboardingSyncService(
          submissionService: _Submission(() {}),
          accountService: AccountService(gateway),
        ).flush(store),
        completes,
        reason: 'signOut throws without Supabase; the stop catches it',
      );
      expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);
      expect(store.pendingSignUp, isNull);
    });

    testWidgets("M-5: ensureAccepted's own check asks for the flag's version", (
      tester,
    ) async {
      final versions = <String>[];
      Widget probe() => MaterialApp(
        home: Builder(
          builder: (context) {
            versions.add(EulaGate.serviceFor(context).version);
            return const SizedBox();
          },
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [signInFlowV2Provider.overrideWithValue(true)],
          child: probe(),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [signInFlowV2Provider.overrideWithValue(false)],
          child: probe(),
        ),
      );
      await tester.pumpWidget(probe());
      expect(versions, ['2', '1', '1']);
    });

    test(
      'M-7: TLS, HTTP and an expired session offline are AccountOffline',
      () async {
        for (final failure in <Object>[
          const HandshakeException('captive portal'),
          const TlsException('x'),
          const HttpException('x'),
          AuthRetryableFetchException(message: 'offline'),
        ]) {
          await expectLater(
            AccountService(
              FakeAccountGateway()..failWith = failure,
            ).completeSignUp(displayName: 'A', birthDate: DateTime.utc(1990)),
            throwsA(isA<AccountOffline>()),
            reason: '$failure',
          );
        }
      },
    );
  });
}
