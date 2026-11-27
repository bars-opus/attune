// Spec 1 W2b, batch 5 carries for the shared files: the replay's under-18
// stop runs before its reset, and its block closes sign-up in the same
// session (ruling C9). Entry gates fix 4 (2026-11-27): EulaGate's group
// went with EulaGate itself (consent is only ever A5's or A5c's now).
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_account_gateway.dart';

class _NoSubmission implements OnboardingSubmissionService {
  @override
  Future<void> submit({
    required OnboardingMode mode,
    required String displayName,
    required List<int> attachmentAnswers,
    required List<String> anchors,
  }) async {}
}

class _ClearPendingFails extends OnboardingStore {
  const _ClearPendingFails(super.prefs, {required super.scope});

  @override
  Future<void> clearPendingSignUp() async => throw StateError('disk full');
}

class _ResetFails extends OnboardingStore {
  const _ResetFails(super.prefs, {required super.scope});

  @override
  Future<void> reset() async => throw StateError('disk full');
}

void main() {
  group('the replay\'s under-18 stop', () {
    late SharedPreferences prefs;
    final pending = PendingSignUp(
      displayName: 'Ama',
      birthDate: DateTime.utc(1990, 1, 2),
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    OnboardingSyncService refused() => OnboardingSyncService(
      submissionService: _NoSubmission(),
      accountService: AccountService(
        FakeAccountGateway()
          ..failWith = FakeAccountGateway.refusal('signup:not_eligible'),
      ),
    );

    test('blocks the phone even when the reset after it fails', () async {
      final store = _ResetFails(prefs, scope: 'user.me');
      await store.savePendingSignUp(pending);
      try {
        await refused().flush(store);
      } catch (_) {
        // Whether a failed reset surfaces is not the point here.
      }
      expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);
    });

    test('fix round 2: dropping the payload comes after the block, so a '
        'throw there never loses it', () async {
      final store = _ClearPendingFails(prefs, scope: 'user.me');
      await store.savePendingSignUp(pending);
      try {
        await refused().flush(store);
      } catch (_) {
        // Whether the failed drop surfaces is not the point here.
      }
      expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);
    });

    test('C9: its block closes sign-up and the guest pass in this '
        'session', () async {
      final routing = RoutingNotifier(
        prefs: prefs,
        flowV2: true,
        guestAgeOk: true,
        currentUserId: () => null,
      );
      expect(appRedirect(routing, RouteNames.signUp), isNull);
      expect(appRedirect(routing, RouteNames.home), isNull);

      final store = OnboardingStore(prefs, scope: 'user.me');
      await store.savePendingSignUp(pending);
      // The default stop: block, then a sign-out that throws here (no
      // Supabase) and is caught.
      await refused().flush(store);

      expect(routing.underAgeBlocked, isTrue);
      expect(appRedirect(routing, RouteNames.signUp), RouteNames.ageStop);
      expect(appRedirect(routing, RouteNames.invite), RouteNames.ageStop);
      expect(appRedirect(routing, RouteNames.home), RouteNames.guestAge);
      expect(store.pendingSignUp, isNull);
    });
  });
}
