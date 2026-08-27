import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/domain/relationship_mode_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Full HomeScreen widget testing requires a live/mocked Supabase client
  // and OnboardingStore, which this codebase has no existing test harness
  // for (see design spec's Testing Evidence section). This test instead
  // covers the one piece of _syncRelationshipMode's logic that's a pure
  // decision independent of any live client: that the resolved mode is
  // only considered "changed" (triggering a write + rebuild) when it
  // actually differs from the current cached mode.
  test('resolved mode differs from cached mode when relationship became active', () {
    const cachedMode = OnboardingMode.couplesPending;
    final resolvedMode = resolveModeFromRelationshipStatus('active');
    expect(resolvedMode == cachedMode, isFalse);
    expect(resolvedMode, OnboardingMode.couples);
  });

  test('resolved mode matches cached mode when nothing changed (no-op case)', () {
    const cachedMode = OnboardingMode.couplesPending;
    final resolvedMode = resolveModeFromRelationshipStatus('pending');
    expect(resolvedMode == cachedMode, isTrue);
  });

  // The reinstall / new-device case. _syncRelationshipMode used to bail on
  // `if (store.mode == null) return;`, which is exactly the state a fresh
  // install is in (SharedPreferences wiped), so the server query that
  // knows about the still-active relationship never ran and the user was
  // stranded on the invite/pairing screen. These lock in that a null
  // cached mode is a state that must still reconcile — not one to skip.
  group('fresh install (no cached mode) still reconciles from server', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    OnboardingStore storeFor(String userId) => OnboardingStore(
      prefs,
      scope: '${OnboardingStore.userScopePrefix}.$userId',
    );

    test('null cached mode is a reconcilable state, not a skippable one', () {
      final store = storeFor('user-1');
      // Precondition: this is what a reinstall actually looks like.
      expect(store.mode, isNull);

      final resolved = resolveModeFromRelationshipStatus('active');
      // The write must be considered necessary; if `null == resolved` were
      // ever true the sync would no-op and the bug would return.
      expect(resolved != store.mode, isTrue);
    });

    test('active relationship restores couples mode after a wipe', () async {
      final store = storeFor('user-1');
      await store.syncModeFromServer(
        resolveModeFromRelationshipStatus('active'),
      );
      expect(store.mode, OnboardingMode.couples);
    });

    test('pending relationship restores couplesPending after a wipe', () async {
      final store = storeFor('user-1');
      await store.syncModeFromServer(
        resolveModeFromRelationshipStatus('pending'),
      );
      expect(store.mode, OnboardingMode.couplesPending);
    });

    test('no relationship row resolves to personal, not a stuck null', () async {
      final store = storeFor('user-1');
      await store.syncModeFromServer(resolveModeFromRelationshipStatus(null));
      expect(store.mode, OnboardingMode.personal);
    });

    // Guards the scope re-check added alongside the fix: the resolved mode
    // must land in the store of the user it was resolved for. Without that
    // check, a sign-out/account-switch mid-query persistently wrote one
    // user's relationship status into another user's cache.
    test('mode is scoped per user and does not leak across accounts', () async {
      await storeFor('user-1').syncModeFromServer(OnboardingMode.couples);
      expect(storeFor('user-1').mode, OnboardingMode.couples);
      expect(storeFor('user-2').mode, isNull);
    });
  });
}
