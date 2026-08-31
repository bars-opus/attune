// lib/features/games/this_or_that/presentation/providers/this_or_that_custom_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repositories/this_or_that_repository.dart';
import '../../data/models/custom_this_or_that_question.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final thisOrThatRepositoryProvider = Provider<ThisOrThatRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return ThisOrThatRepository(supabase);
});

final currentUserIdProvider = Provider<String?>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return supabase.auth.currentUser?.id;
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
  final supabase = ref.read(supabaseClientProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  final userId = supabase.auth.currentUser?.id;
  if (relationshipId == null || userId == null) return null;

  final response =
      await supabase
          .from('relationships')
          .select('user_a, user_b')
          .eq('id', relationshipId)
          .single();

  final partnerId =
      response['user_a'] == userId ? response['user_b'] : response['user_a'];

  final profileRes =
      await supabase
          .from('profiles')
          .select('display_name')
          .eq('id', partnerId)
          .single();

  return profileRes['display_name'] as String? ?? 'Partner';
});

// My custom questions
final myThisOrThatCustomQuestionsProvider =
    FutureProvider<List<CustomThisOrThatQuestion>>((ref) async {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) return [];
      final repository = ref.read(thisOrThatRepositoryProvider);
      final questions = await repository.getMyCustomQuestions(userId);
      return questions
          .map(
            (question) => CustomThisOrThatQuestion(
              id: question.id,
              userId: question.userId,
              questionText: question.questionText,
              optionA: question.optionA,
              optionB: question.optionB,
              emojiA: question.emojiA,
              emojiB: question.emojiB,
              tone: question.tone,
              isPrivate: question.isPrivate,
              timesUsed: question.timesUsed,
              lastUsedAt: question.lastUsedAt,
              createdAt: question.createdAt,
            ),
          )
          .toList();
    });

// Partner's custom questions
final partnerThisOrThatCustomQuestionsProvider =
    FutureProvider<List<CustomThisOrThatQuestion>>((ref) async {
      final userId = ref.read(currentUserIdProvider);
      final relationshipId = await ref.read(
        currentRelationshipIdProvider.future,
      );
      if (userId == null || relationshipId == null) return [];
      final repository = ref.read(thisOrThatRepositoryProvider);
      return repository.getPartnerCustomQuestions(relationshipId, userId);
    });

// Create custom question
final createThisOrThatCustomQuestionProvider = FutureProvider.family<
  void,
  ({
    String questionText,
    String optionA,
    String optionB,
    String? emojiA,
    String? emojiB,
    String tone,
    bool isPrivate,
  })
>((ref, params) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');
  final repository = ref.read(thisOrThatRepositoryProvider);
  await repository.createCustomQuestion(
    userId: userId,
    questionText: params.questionText,
    optionA: params.optionA,
    optionB: params.optionB,
    emojiA: params.emojiA,
    emojiB: params.emojiB,
    tone: params.tone,
    isPrivate: params.isPrivate,
  );
});

// Delete custom question
final deleteThisOrThatCustomQuestionProvider =
    FutureProvider.family<void, String>((ref, questionId) async {
      final repository = ref.read(thisOrThatRepositoryProvider);
      await repository.deleteCustomQuestion(questionId);
    });

// Toggle privacy
final toggleThisOrThatCustomPrivacyProvider =
    FutureProvider.family<void, ({String id, bool isPrivate})>((
      ref,
      params,
    ) async {
      final repository = ref.read(thisOrThatRepositoryProvider);
      await repository.updateCustomQuestionPrivacy(params.id, params.isPrivate);
    });

// Toggle community share
final toggleThisOrThatCommunityShareProvider =
    FutureProvider.family<void, ({String id, bool share})>((ref, params) async {
      final repository = ref.read(thisOrThatRepositoryProvider);
      await repository.toggleShareToCommunity(params.id, params.share);
    });

// Report custom question
final reportThisOrThatCustomQuestionProvider =
    FutureProvider.family<void, ({String id, String reason})>((
      ref,
      params,
    ) async {
      final repository = ref.read(thisOrThatRepositoryProvider);
      await repository.reportCustomQuestion(params.id, params.reason);
    });
