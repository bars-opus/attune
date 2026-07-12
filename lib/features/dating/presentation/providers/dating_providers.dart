import 'package:attune/features/dating/data/models/dating_enrollment.dart';
import 'package:attune/features/dating/data/models/dating_introduction.dart';
import 'package:attune/features/dating/data/repositories/dating_repository.dart';
import 'package:attune/features/dating/domain/services/dating_feature_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final datingSupabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final datingRepositoryProvider = Provider<DatingRepository>((ref) {
  final supabase = ref.read(datingSupabaseClientProvider);
  return DatingRepository(supabase);
});

final currentDatingUserIdProvider = Provider<String?>((ref) {
  final supabase = ref.read(datingSupabaseClientProvider);
  return supabase.auth.currentUser?.id;
});

final datingModeEnabledProvider = FutureProvider<bool>((ref) {
  // DATING-H1: derive availability from the server RPC, not the raw flags table.
  return DatingFeatureFlags.isDatingModeAvailable(
    ref.watch(datingSupabaseClientProvider),
  );
});

final datingEligibilityProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  return ref.read(datingRepositoryProvider).getEligibility();
});

final datingEnrollmentProvider = FutureProvider<DatingEnrollment?>((ref) async {
  return ref.read(datingRepositoryProvider).getEnrollment();
});

final optInToDatingProvider = FutureProvider.family<
  DatingEnrollment,
  ({String termsVersion})
>((ref, params) async {
  final repository = ref.read(datingRepositoryProvider);
  final enrollment = await repository.optIn(termsVersion: params.termsVersion);
  ref.invalidate(datingEligibilityProvider);
  ref.invalidate(datingEnrollmentProvider);
  return enrollment;
});

final activateDatingProfileProvider = FutureProvider<DatingEnrollment>((
  ref,
) async {
  final repository = ref.read(datingRepositoryProvider);
  final enrollment = await repository.activateProfile();
  ref.invalidate(datingEnrollmentProvider);
  ref.invalidate(datingIntroductionsProvider);
  return enrollment;
});

final pauseDatingProvider = FutureProvider<DatingEnrollment>((ref) async {
  final repository = ref.read(datingRepositoryProvider);
  final enrollment = await repository.pause();
  ref.invalidate(datingEnrollmentProvider);
  ref.invalidate(datingIntroductionsProvider);
  return enrollment;
});

final resumeDatingProvider = FutureProvider<DatingEnrollment>((ref) async {
  final repository = ref.read(datingRepositoryProvider);
  final enrollment = await repository.resume();
  ref.invalidate(datingEnrollmentProvider);
  ref.invalidate(datingIntroductionsProvider);
  return enrollment;
});

final exitDatingProvider = FutureProvider<DatingEnrollment>((ref) async {
  final repository = ref.read(datingRepositoryProvider);
  final enrollment = await repository.exit();
  ref.invalidate(datingEnrollmentProvider);
  ref.invalidate(datingIntroductionsProvider);
  ref.invalidate(datingMatchesProvider);
  return enrollment;
});

final recordDatingConsentProvider = FutureProvider.family<
  void,
  ({String termsVersion, bool dataConsent, bool adultsOnlyConfirmed})
>((ref, params) async {
  final repository = ref.read(datingRepositoryProvider);
  await repository.recordConsent(
    purpose: 'dating_opt_in',
    granted: true,
    policyVersion: params.termsVersion,
    categories: const ['dating_mode'],
  );
  await repository.recordConsent(
    purpose: 'dating_terms',
    granted: true,
    policyVersion: params.termsVersion,
    categories: const ['dating_mode', 'privacy_notice'],
  );
  await repository.recordConsent(
    purpose: 'historical_data',
    granted: params.dataConsent,
    policyVersion: params.termsVersion,
    categories: const ['own_historical_summaries'],
  );
  await repository.recordConsent(
    purpose: 'age_gate',
    granted: params.adultsOnlyConfirmed,
    policyVersion: params.termsVersion,
    categories: const ['adults_only_confirmation'],
  );
});

final datingProfileProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  return ref.read(datingRepositoryProvider).getProfile();
});

final saveDatingProfileProvider = FutureProvider.family<
  Map<String, dynamic>,
  ({
    String displayName,
    String cityRegionCode,
    String relationshipIntention,
    int minAge,
    int maxAge,
    String? bio,
  })
>((ref, params) async {
  final repository = ref.read(datingRepositoryProvider);
  final result = await repository.saveProfile(
    displayName: params.displayName,
    cityRegionCode: params.cityRegionCode,
    relationshipIntention: params.relationshipIntention,
    minAge: params.minAge,
    maxAge: params.maxAge,
    bio: params.bio,
  );
  ref.invalidate(datingProfileProvider);
  ref.invalidate(datingEnrollmentProvider);
  return result;
});

final datingIntroductionsProvider = FutureProvider<List<DatingIntroduction>>((
  ref,
) async {
  return ref.read(datingRepositoryProvider).getIntroductions();
});

final actOnIntroductionProvider =
    FutureProvider.family<void, ({String introductionId, String action})>((
      ref,
      params,
    ) async {
      await ref
          .read(datingRepositoryProvider)
          .expressInterest(
            introductionId: params.introductionId,
            action: params.action,
          );
      ref.invalidate(datingIntroductionsProvider);
      ref.invalidate(datingMatchesProvider);
    });

final datingMatchesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(datingRepositoryProvider).getMatches();
});

final unmatchDatingProvider = FutureProvider.family<void, String>((
  ref,
  matchId,
) async {
  await ref.read(datingRepositoryProvider).unmatch(matchId);
  ref.invalidate(datingMatchesProvider);
});

final blockDatingIntroductionProvider = FutureProvider.family<void, String>((
  ref,
  introductionId,
) async {
  await ref.read(datingRepositoryProvider).blockIntroduction(introductionId);
  ref.invalidate(datingIntroductionsProvider);
  ref.invalidate(datingMatchesProvider);
});

final blockDatingMatchProvider = FutureProvider.family<void, String>((
  ref,
  matchId,
) async {
  await ref.read(datingRepositoryProvider).blockMatch(matchId);
  ref.invalidate(datingIntroductionsProvider);
  ref.invalidate(datingMatchesProvider);
});

final reportDatingIntroductionProvider = FutureProvider.family<
  void,
  ({String introductionId, String category, String? details})
>((ref, params) async {
  await ref
      .read(datingRepositoryProvider)
      .reportIntroduction(
        introductionId: params.introductionId,
        category: params.category,
        details: params.details,
      );
});

final reportDatingMatchProvider = FutureProvider.family<
  void,
  ({String matchId, String category, String? details})
>((ref, params) async {
  await ref
      .read(datingRepositoryProvider)
      .reportMatch(
        matchId: params.matchId,
        category: params.category,
        details: params.details,
      );
});

final recordDateReflectionProvider = FutureProvider.family<
  void,
  ({String matchId, String response, String? note})
>((ref, params) async {
  await ref
      .read(datingRepositoryProvider)
      .saveDateReflection(
        matchId: params.matchId,
        response: params.response,
        note: params.note,
      );
});

final deleteDateReflectionProvider = FutureProvider.family<void, String>((
  ref,
  matchId,
) async {
  await ref
      .read(datingRepositoryProvider)
      .deleteDateReflection(matchId: matchId);
});

final deleteDatingProfileProvider = FutureProvider<void>((ref) async {
  await ref.read(datingRepositoryProvider).deleteProfile();
  ref.invalidate(datingProfileProvider);
  ref.invalidate(datingEnrollmentProvider);
  ref.invalidate(datingIntroductionsProvider);
  ref.invalidate(datingMatchesProvider);
});
