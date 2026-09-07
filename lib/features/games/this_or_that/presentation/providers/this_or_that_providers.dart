// lib/features/games/this_or_that/presentation/providers/this_or_that_providers.dart

import 'dart:async';

import 'package:attune/features/games/this_or_that/data/models/custom_question.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/data/repositories/this_or_that_repository.dart';
import 'package:attune/features/games/this_or_that/data/services/this_or_that_answer_outbox.dart';
import 'package:attune/features/games/this_or_that/domain/services/scoring_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final thisOrThatRepositoryProvider = Provider<ThisOrThatRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return ThisOrThatRepository(supabase);
});

final thisOrThatAnswerOutboxProvider = Provider<ThisOrThatAnswerOutbox>((ref) {
  return const SecureThisOrThatAnswerOutbox();
});

final scoringServiceProvider = Provider<ScoringService>((ref) {
  return ScoringService();
});

// Current user ID
final currentUserIdProvider = Provider<String?>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return supabase.auth.currentUser?.id;
});

// Current relationship ID
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

final relationshipMembersProvider =
    FutureProvider.family<({String userA, String userB}), String>((
      ref,
      relationshipId,
    ) async {
      final supabase = ref.read(supabaseClientProvider);
      final response =
          await supabase
              .from('relationships')
              .select('user_a, user_b')
              .eq('id', relationshipId)
              .single();

      return (
        userA: response['user_a'] as String,
        userB: response['user_b'] as String,
      );
    });

// Create new session
final createThisOrThatSessionProvider = FutureProvider.autoDispose
    .family<ThisOrThatSession, ({String relationshipId, String tone})>((
      ref,
      params,
    ) async {
      final repository = ref.read(thisOrThatRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) throw Exception('Not authenticated');

      final idempotencyKey = '${DateTime.now().millisecondsSinceEpoch}_$userId';

      return await repository.createSession(
        relationshipId: params.relationshipId,
        initiatorId: userId,
        tone: params.tone,
        idempotencyKey: idempotencyKey,
      );
    });

// Accept session
final acceptThisOrThatSessionProvider = FutureProvider.autoDispose.family<
  ThisOrThatSession,
  ({String sessionId, bool intimateConsent, String? fallbackTone})
>((ref, params) async {
  final repository = ref.read(thisOrThatRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  return await repository.acceptSession(
    sessionId: params.sessionId,
    userId: userId,
    intimateConsent: params.intimateConsent,
    fallbackTone: params.fallbackTone,
  );
});

// Get active session
final activeThisOrThatSessionProvider = FutureProvider<ThisOrThatSession?>((
  ref,
) async {
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return null;

  final supabase = ref.read(supabaseClientProvider);
  final response =
      await supabase
          .from('game_sessions')
          .select('*')
          .eq('relationship_id', relationshipId)
          .eq('game_type', 'this_or_that')
          .inFilter('status', ['invited', 'active'])
          .maybeSingle();

  return response != null ? ThisOrThatSession.fromJson(response) : null;
});

// Submit answer
final submitAnswerProvider = FutureProvider.autoDispose
    .family<void, ({String roundId, String choice, bool isPartnerA})>((
      ref,
      params,
    ) async {
      final repository = ref.read(thisOrThatRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) throw Exception('Not authenticated');

      await repository.submitAnswer(
        roundId: params.roundId,
        userId: userId,
        choice: params.choice,
        isPartnerA: params.isPartnerA,
      );
    });

// Send reminder for session
final sendReminderProvider = FutureProvider.autoDispose.family<void, String>((
  ref,
  sessionId,
) async {
  final repository = ref.read(thisOrThatRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  await repository.sendReminder(sessionId, userId);
});

final abandonSessionProvider = FutureProvider.autoDispose.family<void, String>((
  ref,
  sessionId,
) async {
  final repository = ref.read(thisOrThatRepositoryProvider);
  await repository.abandonSession(sessionId);
  ref.invalidate(activeThisOrThatSessionProvider);
});

// Add to this_or_that_providers.dart

// Custom questions providers
final myCustomQuestionsProvider = FutureProvider<List<CustomQuestion>>((
  ref,
) async {
  final repository = ref.read(thisOrThatRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) return [];
  return await repository.getMyCustomQuestions(userId);
});

final partnerCustomQuestionsProvider = FutureProvider<List<CustomQuestion>>((
  ref,
) async {
  final repository = ref.read(thisOrThatRepositoryProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  final userId = ref.read(currentUserIdProvider);
  if (relationshipId == null || userId == null) return [];

  final partnerId = await repository.getPartnerId(relationshipId, userId);
  return await repository.getMyCustomQuestions(partnerId);
});

final createCustomQuestionProvider = FutureProvider.family<
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
  final repository = ref.read(thisOrThatRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

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

final deleteCustomQuestionProvider = FutureProvider.autoDispose
    .family<void, String>((ref, questionId) async {
      final repository = ref.read(thisOrThatRepositoryProvider);
      await repository.deleteCustomQuestion(questionId);
    });

final toggleCustomQuestionPrivacyProvider = FutureProvider.autoDispose
    .family<void, ({String id, bool isPrivate})>((ref, params) async {
      final repository = ref.read(thisOrThatRepositoryProvider);
      await repository.updateCustomQuestionPrivacy(params.id, params.isPrivate);
    });

final reportCustomQuestionProvider = FutureProvider.autoDispose
    .family<void, ({String id, String reason})>((ref, params) async {
      final repository = ref.read(thisOrThatRepositoryProvider);
      await repository.reportCustomQuestion(params.id, params.reason);
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
// Add to this_or_that_providers.dart

// Completed sessions paginated
final completedSessionsProvider = FutureProvider<List<ThisOrThatSession>>((
  ref,
) async {
  final repository = ref.read(thisOrThatRepositoryProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  final userId = ref.read(currentUserIdProvider);
  if (relationshipId == null || userId == null) return [];

  return await repository.getCompletedSessions(relationshipId, userId);
});

// Completed sessions with cursor for pagination
final completedSessionsCursorProvider = FutureProvider.family<
  List<ThisOrThatSession>,
  String?
>((ref, cursor) async {
  final repository = ref.read(thisOrThatRepositoryProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  final userId = ref.read(currentUserIdProvider);
  if (relationshipId == null || userId == null) return [];

  return await repository.getCompletedSessions(
    relationshipId,
    userId,
    cursor: cursor,
  );
});

// Single session details
final sessionProvider = FutureProvider.family<ThisOrThatSession?, String>((
  ref,
  sessionId,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final response =
      await supabase
          .from('game_sessions')
          .select('*')
          .eq('id', sessionId)
          .maybeSingle();

  return response != null ? ThisOrThatSession.fromJson(response) : null;
});

// Session rounds
final sessionRoundsProvider = FutureProvider.family<List<GameRound>, String>((
  ref,
  sessionId,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final response = await supabase.rpc(
    'this_or_that_round_state',
    params: {'p_session_id': sessionId},
  );

  return (response as List<dynamic>)
      .map((json) => GameRound.fromJson(json as Map<String, dynamic>))
      .toList();
});

/// Safe live signal for This or That.
///
/// Round answer rows contain private picks, so this feature never subscribes
/// to their realtime payload. A trigger bumps the answer-free session row;
/// polling remains as a fallback when realtime is unavailable.
final thisOrThatSessionPulseProvider = StreamProvider.family<void, String>((
  ref,
  sessionId,
) async* {
  final supabase = ref.read(supabaseClientProvider);
  final controller = StreamController<void>.broadcast();
  final poll = Timer.periodic(const Duration(seconds: 2), (_) {
    if (!controller.isClosed) controller.add(null);
  });
  final channel =
      supabase
          .channel('this-or-that-session:$sessionId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'game_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: sessionId,
            ),
            callback: (_) {
              if (!controller.isClosed) controller.add(null);
            },
          )
          .subscribe();

  ref.onDispose(() {
    poll.cancel();
    unawaited(controller.close());
    unawaited(supabase.removeChannel(channel));
  });

  yield* controller.stream;
});

// Hide session
final hideSessionProvider = FutureProvider.autoDispose.family<void, String>((
  ref,
  sessionId,
) async {
  final repository = ref.read(thisOrThatRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  await repository.hideSession(sessionId, userId);
  ref.invalidate(completedSessionsProvider);
});

final advanceSessionProvider = FutureProvider.autoDispose.family<
  void,
  ({
    String sessionId,
    int nextRound,
    int matchCount,
    int totalRoundsCompleted,
    bool isCompleted,
  })
>((ref, params) async {
  final repository = ref.read(thisOrThatRepositoryProvider);
  await repository.advanceSession(
    sessionId: params.sessionId,
    nextRound: params.nextRound,
    matchCount: params.matchCount,
    totalRoundsCompleted: params.totalRoundsCompleted,
    isCompleted: params.isCompleted,
  );
  ref.invalidate(activeThisOrThatSessionProvider);
  ref.invalidate(sessionProvider(params.sessionId));
  ref.invalidate(sessionRoundsProvider(params.sessionId));
});

final chooseNextQuestionProvider = FutureProvider.autoDispose.family<
  bool,
  ({String sessionId, int nextRound, String source, String? customOwnerId})
>((ref, params) async {
  final repository = ref.read(thisOrThatRepositoryProvider);
  final usedPresetFallback = await repository.prepareNextRound(
    sessionId: params.sessionId,
    roundNumber: params.nextRound,
    source: params.source,
    customOwnerId: params.customOwnerId,
  );
  ref.invalidate(activeThisOrThatSessionProvider);
  ref.invalidate(sessionProvider(params.sessionId));
  ref.invalidate(sessionRoundsProvider(params.sessionId));
  return usedPresetFallback;
});
