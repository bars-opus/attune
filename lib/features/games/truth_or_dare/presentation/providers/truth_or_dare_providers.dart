// lib/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart

import 'package:attune/features/games/data/models/game_session.dart';
import 'package:attune/features/games/truth_or_dare/data/models/custom_truth_or_dare_question.dart';
import 'package:attune/features/games/truth_or_dare/data/repositories/truth_or_dare_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final truthOrDareRepositoryProvider = Provider<TruthOrDareRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return TruthOrDareRepository(supabase);
});

// Current user ID
final currentUserIdProvider = Provider<String?>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return supabase.auth.currentUser?.id;
});

// Current relationship ID
final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) return null;
  final repository = ref.read(truthOrDareRepositoryProvider);
  return await repository.getRelationshipId(userId);
});

// Partner name
final partnerNameProvider = FutureProvider<String?>((ref) async {
  final userId = ref.read(currentUserIdProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (userId == null || relationshipId == null) return null;
  final repository = ref.read(truthOrDareRepositoryProvider);
  return await repository.getPartnerName(relationshipId, userId);
});

final relationshipMembersProvider =
    FutureProvider.family<({String userA, String userB}), String>((
      ref,
      relationshipId,
    ) async {
      final repository = ref.read(truthOrDareRepositoryProvider);
      return repository.getRelationshipMembers(relationshipId);
    });

final partnerIdProvider = FutureProvider.family<String, String>((ref, sessionId) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  final session = await ref
      .read(supabaseClientProvider)
      .from('game_sessions')
      .select('relationship_id')
      .eq('id', sessionId)
      .single();

  final repository = ref.read(truthOrDareRepositoryProvider);
  return repository.getPartnerId(session['relationship_id'] as String, userId);
});

final createTruthOrDareSessionProvider = FutureProvider.family<
  GameSession,
  ({String relationshipId, String tone})
>((ref, params) async {
  final repository = ref.read(truthOrDareRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  final idempotencyKey = '${DateTime.now().millisecondsSinceEpoch}_$userId';
  return repository.createSession(
    relationshipId: params.relationshipId,
    initiatorId: userId,
    tone: params.tone,
    idempotencyKey: idempotencyKey,
  );
});

final acceptTruthOrDareSessionProvider = FutureProvider.family<
  GameSession,
  ({String sessionId, bool intimateConsent, String? fallbackTone})
>((ref, params) async {
  final repository = ref.read(truthOrDareRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  return repository.acceptSession(
    sessionId: params.sessionId,
    userId: userId,
    intimateConsent: params.intimateConsent,
    fallbackTone: params.fallbackTone,
  );
});

final activeTruthOrDareSessionProvider = FutureProvider<GameSession?>((ref) async {
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return null;

  final repository = ref.read(truthOrDareRepositoryProvider);
  return repository.getActiveSession(relationshipId);
});

final truthOrDareSessionProvider = FutureProvider.family<GameSession?, String>((
  ref,
  sessionId,
) async {
  final repository = ref.read(truthOrDareRepositoryProvider);
  return repository.getSession(sessionId);
});

// Custom questions
final myCustomTruthOrDareQuestionsProvider = FutureProvider<List<CustomTruthOrDareQuestion>>((ref) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) return [];
  final repository = ref.read(truthOrDareRepositoryProvider);
  return await repository.getMyCustomQuestions(userId);
});

final partnerCustomTruthOrDareQuestionsProvider = FutureProvider<List<CustomTruthOrDareQuestion>>((ref) async {
  final userId = ref.read(currentUserIdProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (userId == null || relationshipId == null) return [];
  final repository = ref.read(truthOrDareRepositoryProvider);
  return await repository.getPartnerCustomQuestions(relationshipId, userId);
});

// Create custom question
final createCustomTruthOrDareQuestionProvider = FutureProvider.family<void, ({
  String questionType,
  String content,
  String tone,
  bool isPrivate,
})>((ref, params) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');
  final repository = ref.read(truthOrDareRepositoryProvider);
  await repository.createCustomQuestion(
    userId: userId,
    questionType: params.questionType,
    content: params.content,
    tone: params.tone,
    isPrivate: params.isPrivate,
  );
});

// Delete custom question
final deleteCustomTruthOrDareQuestionProvider = FutureProvider.family<void, String>((ref, questionId) async {
  final repository = ref.read(truthOrDareRepositoryProvider);
  await repository.deleteCustomQuestion(questionId);
});

// Toggle privacy
final toggleCustomTruthOrDarePrivacyProvider = FutureProvider.family<void, ({
  String id,
  bool isPrivate,
})>((ref, params) async {
  final repository = ref.read(truthOrDareRepositoryProvider);
  await repository.updateCustomQuestionPrivacy(params.id, params.isPrivate);
});

// Report custom question
final reportCustomTruthOrDareQuestionProvider = FutureProvider.family<void, ({
  String id,
  String reason,
})>((ref, params) async {
  final repository = ref.read(truthOrDareRepositoryProvider);
  await repository.reportCustomQuestion(params.id, params.reason);
});

// Select random type
final randomTypeProvider = Provider<String>((ref) {
  final repository = ref.read(truthOrDareRepositoryProvider);
  return repository.selectRandomType();
});

// Select question for round
final selectQuestionForRoundProvider = FutureProvider.family<Map<String, dynamic>, ({
  String tone,
  String questionType,
  String sessionId,
})>((ref, params) async {
  final userId = ref.read(currentUserIdProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (userId == null || relationshipId == null) throw Exception('Not authenticated');
  final repository = ref.read(truthOrDareRepositoryProvider);
  return await repository.selectQuestionForRound(
    relationshipId: relationshipId,
    userId: userId,
    tone: params.tone,
    questionType: params.questionType,
    sessionId: params.sessionId,
  );
});

final createTruthOrDareRoundProvider = FutureProvider.family<
  TruthOrDareRound,
  ({
    String sessionId,
    int roundNumber,
    String activePartnerId,
    Map<String, dynamic> questionData,
  })
>((ref, params) async {
  final repository = ref.read(truthOrDareRepositoryProvider);
  return repository.createRoundForTurn(
    sessionId: params.sessionId,
    roundNumber: params.roundNumber,
    activePartnerId: params.activePartnerId,
    questionData: params.questionData,
  );
});

final truthOrDareSessionRoundsProvider =
    FutureProvider.family<List<TruthOrDareRound>, String>((ref, sessionId) async {
      final repository = ref.read(truthOrDareRepositoryProvider);
      return repository.getSessionRounds(sessionId);
    });

final abandonTruthOrDareSessionProvider = FutureProvider.family<void, String>((
  ref,
  sessionId,
) async {
  final repository = ref.read(truthOrDareRepositoryProvider);
  await repository.abandonSession(sessionId);
  ref.invalidate(activeTruthOrDareSessionProvider);
});

final advanceTruthOrDareSessionProvider = FutureProvider.family<
  void,
  ({String sessionId, int nextRound, bool isCompleted})
>((ref, params) async {
  final repository = ref.read(truthOrDareRepositoryProvider);
  await repository.advanceSession(
    sessionId: params.sessionId,
    nextRound: params.nextRound,
    isCompleted: params.isCompleted,
  );
  ref.invalidate(truthOrDareSessionProvider(params.sessionId));
  ref.invalidate(truthOrDareSessionRoundsProvider(params.sessionId));
  ref.invalidate(activeTruthOrDareSessionProvider);
});

// Session history (metadata only)
final truthOrDareSessionHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = ref.read(currentUserIdProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (userId == null || relationshipId == null) return [];
  final repository = ref.read(truthOrDareRepositoryProvider);
  return await repository.getSessionHistory(relationshipId: relationshipId, userId: userId);
});
