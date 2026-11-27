// Spec 1 W2b, batch 3 extras to Task 6: no account call without a queued
// A5, and the replay runs before today's submission. The last group pins
// the batch 3 review's fix round 1 (M-2, M-3, M-4, M-7). Entry gates fix 4
// (2026-11-27): the EULA sheet's version tests, the legacy flow's joined
// step and M-5 went with EulaGate and OnboardingFlow.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/fake_account_gateway.dart';

const _me = '5f1a0000-0000-0000-0000-0000000000bb';

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
