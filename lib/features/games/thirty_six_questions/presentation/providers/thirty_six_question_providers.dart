// lib/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/providers/locale_provider.dart';
import '../../data/models/thirty_six_question_chapter.dart';
import '../../data/models/thirty_six_question_journey.dart';
import '../../data/repositories/thirty_six_question_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final thirtySixQuestionRepositoryProvider =
    Provider<ThirtySixQuestionRepository>((ref) {
      return ThirtySixQuestionRepository(ref.read(supabaseClientProvider));
    });

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.read(supabaseClientProvider).auth.currentUser?.id;
});

final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final response =
      await supabase
          .from('relationships')
          .select('id')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .eq('status', 'active')
          .maybeSingle();

  return response?['id'] as String?;
});

final partnerNameProvider = FutureProvider<String?>((ref) async {
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  final userId = ref.read(currentUserIdProvider);
  if (relationshipId == null || userId == null) return null;

  return ref
      .read(thirtySixQuestionRepositoryProvider)
      .getPartnerName(relationshipId, userId);
});

final activeThirtySixJourneyProvider =
    FutureProvider<ThirtySixQuestionJourney?>((ref) async {
      final relationshipId = await ref.read(
        currentRelationshipIdProvider.future,
      );
      if (relationshipId == null) return null;
      return ref
          .read(thirtySixQuestionRepositoryProvider)
          .getActiveJourney(relationshipId);
    });

final thirtySixJourneysProvider =
    FutureProvider<List<ThirtySixQuestionJourney>>((ref) async {
      final supabase = ref.read(supabaseClientProvider);
      final relationshipId = await ref.read(
        currentRelationshipIdProvider.future,
      );
      if (relationshipId == null) return [];

      final response = await supabase
          .from('thirty_six_question_journeys')
          .select('*')
          .eq('relationship_id', relationshipId)
          .order('created_at', ascending: false);

      return response
          .map((json) => ThirtySixQuestionJourney.fromJson(json))
          .toList();
    });

final thirtySixJourneyProvider =
    FutureProvider.family<ThirtySixQuestionJourney?, String>((ref, journeyId) {
      return ref
          .read(thirtySixQuestionRepositoryProvider)
          .getJourney(journeyId);
    });

final journeyChaptersProvider =
    FutureProvider.family<List<ThirtySixQuestionChapter>, String>((
      ref,
      journeyId,
    ) {
      return ref
          .read(thirtySixQuestionRepositoryProvider)
          .getJourneyChapters(journeyId);
    });

final inviteToChapterProvider = FutureProvider.family<
  ThirtySixQuestionChapter,
  ({String journeyId, int chapter})
>((ref, params) async {
  final userId = ref.read(currentUserIdProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  final locale = ref.read(currentLocaleProvider).languageCode;
  if (userId == null || relationshipId == null) {
    throw Exception('Not authenticated');
  }

  final chapter = await ref
      .read(thirtySixQuestionRepositoryProvider)
      .sendContinuationInvite(
        journeyId: params.journeyId,
        relationshipId: relationshipId,
        initiatorId: userId,
        chapter: params.chapter,
        locale: locale,
      );

  ref.invalidate(activeThirtySixJourneyProvider);
  ref.invalidate(journeyChaptersProvider(params.journeyId));
  return chapter;
});

final acceptChapterInvitationProvider =
    FutureProvider.family<ThirtySixQuestionChapter, String>((
      ref,
      sessionId,
    ) async {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) throw Exception('Not authenticated');

      final chapter = await ref
          .read(thirtySixQuestionRepositoryProvider)
          .acceptChapterInvitation(sessionId: sessionId);

      if (chapter.journeyId.isNotEmpty) {
        ref.invalidate(journeyChaptersProvider(chapter.journeyId));
      }
      return chapter;
    });

final chapterReflectionProvider = FutureProvider.family<
  Map<String, dynamic>?,
  ({String journeyId, int chapter})
>((ref, params) {
  return ref
      .read(thirtySixQuestionRepositoryProvider)
      .getChapterReflection(
        journeyId: params.journeyId,
        chapter: params.chapter,
      );
});

final journeyReflectionProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, journeyId) {
      return ref
          .read(thirtySixQuestionRepositoryProvider)
          .getJourneyReflection(journeyId: journeyId);
    });

final generateChapterReflectionProvider = FutureProvider.family<
  Map<String, dynamic>,
  ({String journeyId, int chapter})
>((ref, params) {
  return ref
      .read(thirtySixQuestionRepositoryProvider)
      .generateChapterReflection(
        journeyId: params.journeyId,
        chapter: params.chapter,
      );
});

final generateJourneyReflectionProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, journeyId) {
      return ref
          .read(thirtySixQuestionRepositoryProvider)
          .generateJourneyReflection(journeyId: journeyId);
    });

final isChapterActiveProvider =
    FutureProvider.family<bool, ({String journeyId, int chapter})>((
      ref,
      params,
    ) async {
      final chapter = await ref
          .read(thirtySixQuestionRepositoryProvider)
          .getActiveChapterForJourney(
            journeyId: params.journeyId,
            chapter: params.chapter,
          );
      return chapter != null;
    });
