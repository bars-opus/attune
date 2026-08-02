import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/domain/relationship_mode_sync.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
