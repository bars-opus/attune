// Spec 1 W2b (§3.3, §3.14): the sign-up RPCs, the queued A5 and its
// replay, EULA v2, and today's onboarding not asking the name twice.
import 'dart:async';

import 'package:attune/features/auth/data/eula_acceptance_service.dart';
import 'package:attune/features/auth/presentation/eula_gate.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_account_gateway.dart';

class _NoSubmission implements OnboardingSubmissionService {
  int calls = 0;

  @override
  Future<void> submit({
    required OnboardingMode mode,
    required String displayName,
    required List<int> attachmentAnswers,
    required List<String> anchors,
  }) async => calls++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late OnboardingStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = OnboardingStore(prefs, scope: 'user.u1');
  });

  group('AccountService', () {
    test('complete_sign_up sends the name, the date and EULA 2', () async {
      final gateway = FakeAccountGateway();
      await AccountService(
        gateway,
      ).completeSignUp(displayName: 'Ɛsi', birthDate: DateTime.utc(1996, 3, 7));
      expect(gateway.calls.single.$1, 'complete_sign_up');
      expect(gateway.calls.single.$2, {
        'p_display_name': 'Ɛsi',
        'p_birth_date': '1996-03-07',
        'p_eula_version': '2',
      });
    });

    test('each refusal is told apart from a transient failure', () async {
      Future<Object?> outcome(Object failure) async {
        final gateway = FakeAccountGateway()..failWith = failure;
        try {
          await AccountService(
            gateway,
          ).completeSignUp(displayName: 'A', birthDate: DateTime.utc(1990));
          return null;
        } catch (error) {
          return error;
        }
      }

      expect(
        ((await outcome(FakeAccountGateway.refusal('signup:not_eligible')))
                as SignUpRefused)
            .reason,
        SignUpRefusal.notEligible,
      );
      expect(
        ((await outcome(FakeAccountGateway.refusal('signup:phone_required')))
                as SignUpRefused)
            .reason,
        SignUpRefusal.phoneRequired,
      );
      expect(
        ((await outcome(FakeAccountGateway.refusal('signup:invalid_name')))
                as SignUpRefused)
            .reason,
        SignUpRefusal.invalid,
      );
      expect(
        await outcome(FakeAccountGateway.refusal('upstream timeout')),
        isA<AccountOffline>(),
      );
      expect(await outcome(TimeoutException('slow')), isA<AccountOffline>());
    });

    test('the home state is read through the W1 model', () async {
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(needs: ['consent', 'path']),
      );
      final state = await AccountService(gateway).homeState();
      expect(state.hasAccount, isTrue);
      expect(state.needs, [HomeNeed.consent, HomeNeed.path]);
    });

    test('A5c records EULA 2', () async {
      final gateway = FakeAccountGateway();
      await AccountService(gateway).acceptUpdatedTerms();
      expect(gateway.calls.single.$1, 'record_eula_acceptance');
      expect(gateway.calls.single.$2, {'p_version': '2'});
    });
  });

  group('the queued A5', () {
    final pending = PendingSignUp(
      displayName: 'Ama',
      birthDate: DateTime.utc(1990, 1, 2),
    );

    test('round-trips in the account scope and is cleared by reset', () async {
      await store.savePendingSignUp(pending);
      expect(store.pendingSignUp!.displayName, 'Ama');
      expect(store.pendingSignUp!.birthDate, DateTime.utc(1990, 1, 2));
      expect(OnboardingStore(prefs, scope: 'user.other').pendingSignUp, isNull);
      await store.reset();
      expect(store.pendingSignUp, isNull);
    });

    test(
      'is replayed before today\'s onboarding submission, then cleared',
      () async {
        final gateway = FakeAccountGateway();
        final submission = _NoSubmission();
        await store.savePendingSignUp(pending);
        await OnboardingSyncService(
          submissionService: submission,
          accountService: AccountService(gateway),
        ).flush(store);
        expect(gateway.count('complete_sign_up'), 1);
        expect(store.pendingSignUp, isNull);
      },
    );

    test('offline it stays for the next launch', () async {
      final gateway =
          FakeAccountGateway()..failWith = TimeoutException('offline');
      await store.savePendingSignUp(pending);
      await OnboardingSyncService(
        submissionService: _NoSubmission(),
        accountService: AccountService(gateway),
      ).flush(store);
      expect(store.pendingSignUp, isNotNull);
    });

    test('an under-18 refusal drops it and runs the stop', () async {
      final gateway =
          FakeAccountGateway()
            ..failWith = FakeAccountGateway.refusal('signup:not_eligible');
      var stopped = 0;
      await store.savePendingSignUp(pending);
      await OnboardingSyncService(
        submissionService: _NoSubmission(),
        accountService: AccountService(gateway),
        onSignUpNotEligible: () async => stopped++,
      ).flush(store);
      expect(store.pendingSignUp, isNull);
      expect(stopped, 1);
      expect(
        AgeGateStore.readBlocked(prefs, DateTime.now()),
        isFalse,
        reason: 'the injected stop replaced the default',
      );
    });
  });

  group('EULA v2', () {
    test('asks only for a missing or older version, compared as numbers', () {
      expect(
        EulaAcceptanceService.needsFor(stored: null, version: '1'),
        isTrue,
      );
      expect(
        EulaAcceptanceService.needsFor(stored: '1', version: '1'),
        isFalse,
      );
      expect(
        EulaAcceptanceService.needsFor(stored: '2', version: '1'),
        isFalse,
        reason: 'never asks someone to step down',
      );
      expect(EulaAcceptanceService.needsFor(stored: '1', version: '2'), isTrue);
      expect(
        EulaAcceptanceService.needsFor(stored: 'v1', version: '1'),
        isTrue,
      );
      expect(EulaAcceptanceService().version, '1');
    });

    testWidgets('EulaGate asks for v2 under flow_signin_v2, v1 otherwise', (
      tester,
    ) async {
      late String on;
      late String off;
      late String bare;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [signInFlowV2Provider.overrideWithValue(true)],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                on = EulaGate.versionFor(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [signInFlowV2Provider.overrideWithValue(false)],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                off = EulaGate.versionFor(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              bare = EulaGate.versionFor(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect((on, off, bare), ('2', '1', '1'));
    });
  });

  group("today's onboarding after a v2 sign-up", () {
    Widget app(OnboardingStore store) => ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: OnboardingFlow(store: store, onComplete: () {}),
            ),
      ),
    );

    testWidgets('skips the name step when A1 already took the name', (
      tester,
    ) async {
      await store.rememberDisplayName('عائشة');
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      expect(find.text('What should Attune call you?'), findsNothing);
      expect(find.text('Are you single or in a relationship?'), findsOneWidget);
    });

    testWidgets('with no name stored it starts at the name step, as today', (
      tester,
    ) async {
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      expect(find.text('What should Attune call you?'), findsOneWidget);
    });
  });
}
