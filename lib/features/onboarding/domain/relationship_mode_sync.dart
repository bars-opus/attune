import 'package:attune/features/onboarding/domain/onboarding_models.dart';

/// Maps a relationships.status value (server source of truth) to the
/// OnboardingMode the client should locally cache. Pure and side-effect
/// free so it's testable without a live Supabase client — the actual
/// server round-trip lives in HomeScreen._syncRelationshipMode.
///
/// 'paused' intentionally resolves to personal, not a distinct mode: no UI
/// in this codebase distinguishes a paused relationship from an ended one
/// on the couples/chat surface (see design spec
/// docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md
/// §1). An unrecognized/future status also resolves to personal rather
/// than throwing, so a server-side enum addition never crashes the client.
OnboardingMode resolveModeFromRelationshipStatus(String? status) {
  switch (status) {
    case 'active':
      return OnboardingMode.couples;
    case 'pending':
      return OnboardingMode.couplesPending;
    default:
      return OnboardingMode.personal;
  }
}
