import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/domain/relationship_mode_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active status resolves to couples', () {
    expect(resolveModeFromRelationshipStatus('active'), OnboardingMode.couples);
  });

  test('pending status resolves to couplesPending', () {
    expect(resolveModeFromRelationshipStatus('pending'), OnboardingMode.couplesPending);
  });

  test('ended status resolves to personal', () {
    expect(resolveModeFromRelationshipStatus('ended'), OnboardingMode.personal);
  });

  test('paused status resolves to personal', () {
    expect(resolveModeFromRelationshipStatus('paused'), OnboardingMode.personal);
  });

  test('null status (no relationship row) resolves to personal', () {
    expect(resolveModeFromRelationshipStatus(null), OnboardingMode.personal);
  });

  test('unrecognized status resolves to personal, not a crash', () {
    expect(resolveModeFromRelationshipStatus('some_future_status'), OnboardingMode.personal);
  });
}
