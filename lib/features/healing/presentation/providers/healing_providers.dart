import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/data/repositories/healing_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef HealingStartContext =
    ({String relationshipId, DateTime breakupAt, String breakupAtSource});

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final healingRepositoryProvider = Provider<HealingRepository>((ref) {
  return HealingRepository(ref.read(supabaseClientProvider));
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.read(supabaseClientProvider).auth.currentUser?.id;
});

final healingJourneyProvider = FutureProvider<HealingJourney?>((ref) async {
  final repository = ref.read(healingRepositoryProvider);
  return repository.getLatestJourney();
});

final healingStartContextProvider = FutureProvider<HealingStartContext?>((
  ref,
) async {
  final repository = ref.read(healingRepositoryProvider);
  final relationship = await repository.getStartableRelationship();
  if (relationship == null || relationship['ended_at'] == null) {
    return null;
  }

  return (
    relationshipId: relationship['id'] as String,
    breakupAt: DateTime.parse(relationship['ended_at'] as String),
    breakupAtSource: 'relationship',
  );
});

final startHealingJourneyProvider =
    FutureProvider.family<HealingJourney, HealingStartContext>((
      ref,
      params,
    ) async {
      final repository = ref.read(healingRepositoryProvider);
      final journey = await repository.getOrCreateJourney(
        relationshipId: params.relationshipId,
        breakupAt: params.breakupAt,
        breakupAtSource: params.breakupAtSource,
      );
      ref.invalidate(healingJourneyProvider);
      return journey;
    });

final updateReflectionProvider = FutureProvider.family<
  void,
  ({String journeyId, Map<String, dynamic> answers})
>((ref, params) async {
  await ref
      .read(healingRepositoryProvider)
      .updateReflection(journeyId: params.journeyId, answers: params.answers);
  ref.invalidate(healingJourneyProvider);
});

final completeReflectionProvider = FutureProvider.family<void, String>((
  ref,
  journeyId,
) async {
  await ref.read(healingRepositoryProvider).completeReflection(journeyId);
  ref.invalidate(healingJourneyProvider);
});

final completePostMortemProvider = FutureProvider.family<
  void,
  ({
    String journeyId,
    String status,
    String? observation,
    String? confidence,
    String? reflectionPrompt,
  })
>((ref, params) async {
  await ref
      .read(healingRepositoryProvider)
      .completePostMortem(
        journeyId: params.journeyId,
        status: params.status,
        observation: params.observation,
        confidence: params.confidence,
        reflectionPrompt: params.reflectionPrompt,
      );
  ref.invalidate(healingJourneyProvider);
});

final completePatternAwarenessProvider = FutureProvider.family<void, String>((
  ref,
  journeyId,
) async {
  await ref.read(healingRepositoryProvider).completePatternAwareness(journeyId);
  ref.invalidate(healingJourneyProvider);
});

final completePortraitProvider = FutureProvider.family<
  void,
  ({
    String journeyId,
    String status,
    String? portraitText,
    String? portraitReflection,
    String? reflectionPrompt,
  })
>((ref, params) async {
  await ref
      .read(healingRepositoryProvider)
      .completePortrait(
        journeyId: params.journeyId,
        status: params.status,
        portraitText: params.portraitText,
        portraitReflection: params.portraitReflection,
        reflectionPrompt: params.reflectionPrompt,
      );
  ref.invalidate(healingJourneyProvider);
});

final submitReadinessProvider = FutureProvider.family<
  Map<String, dynamic>,
  ({String journeyId, Map<String, dynamic> answers})
>((ref, params) async {
  final result = await ref
      .read(healingRepositoryProvider)
      .submitReadiness(journeyId: params.journeyId, answers: params.answers);
  ref.invalidate(healingJourneyProvider);
  ref.invalidate(latestReadinessAttemptProvider(params.journeyId));
  return result;
});

final completeReadinessWithoutScoreProvider =
    FutureProvider.family<void, String>((ref, journeyId) async {
      await ref
          .read(healingRepositoryProvider)
          .completeReadinessWithoutScore(journeyId);
      ref.invalidate(healingJourneyProvider);
    });

final latestReadinessAttemptProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((
      ref,
      journeyId,
    ) async {
      return ref
          .read(healingRepositoryProvider)
          .getLatestReadinessAttempt(journeyId);
    });
