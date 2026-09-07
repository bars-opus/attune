// lib/features/games/this_or_that/data/repositories/this_or_that_repository.dart

import 'dart:convert';
import 'package:attune/features/games/this_or_that/data/models/custom_question.dart';
import 'package:attune/features/games/this_or_that/data/models/custom_this_or_that_question.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_question.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ThisOrThatRepository {
  final SupabaseClient _supabase;

  ThisOrThatRepository(this._supabase);

  // ============================================================
  // Session Management
  // ============================================================

  Future<ThisOrThatSession> createSession({
    required String relationshipId,
    required String initiatorId,
    required String tone,
    required String idempotencyKey,
  }) async {
    final response = await _supabase.rpc(
      'create_this_or_that_session',
      params: {
        'p_relationship_id': relationshipId,
        'p_tone': tone,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _sessionFromRpc(response);
  }

  Future<ThisOrThatSession> acceptSession({
    required String sessionId,
    required String userId,
    required bool intimateConsent,
    String? fallbackTone,
  }) async {
    final response = await _supabase.rpc(
      'accept_this_or_that_session',
      params: {
        'p_session_id': sessionId,
        'p_intimate_consent': intimateConsent,
        'p_fallback_tone': fallbackTone,
      },
    );
    return _sessionFromRpc(response);
  }

  // ============================================================
  // Question Selection
  // ============================================================

  Future<List<dynamic>> getAvailableCustomQuestions(
    String relationshipId,
    String tone,
  ) async {
    final userId = _supabase.auth.currentUser?.id;
    final partnerId = await getPartnerId(relationshipId, userId!);

    final response = await _supabase
        .from('custom_this_or_that_questions')
        .select('*')
        .or('user_id.eq.$userId,user_id.eq.$partnerId')
        .eq('is_private', false)
        .eq('hidden_for_review', false)
        .eq('tone', tone)
        .order('times_used', ascending: true)
        .order('last_used_at', ascending: true, nullsFirst: true);

    return response.map((json) => CustomQuestion.fromJson(json)).toList();
  }

  Future<List<ThisOrThatQuestion>> getUnseenPresetQuestions(
    String relationshipId,
    String tone,
  ) async {
    final seenIds = await _getSeenQuestionIds(relationshipId);

    final query = _supabase
        .from('game_questions')
        .select('*')
        .eq('game_type', 'this_or_that')
        .eq('active', true)
        .eq('tone', tone);

    final response = await query;

    List<ThisOrThatQuestion> questions =
        response
            .map((json) => ThisOrThatQuestion.fromJson(json))
            .where((q) => !seenIds.contains(q.id))
            .toList();

    // Intimate tone guarantee: at least 5 questions must be tone_level=4
    if (tone == 'intimate') {
      final intimateQuestions =
          questions.where((q) => q.toneLevel == 4).toList();
      if (intimateQuestions.length < 5) {
        final spicyQuestions =
            questions.where((q) => q.toneLevel == 3).toList();
        questions = [...intimateQuestions, ...spicyQuestions];
      }
    }

    return questions;
  }

  Future<List<ThisOrThatQuestion>> getPresetQuestions(String tone) async {
    final response = await _supabase
        .from('game_questions')
        .select('*')
        .eq('game_type', 'this_or_that')
        .eq('active', true)
        .eq('tone', tone);

    return response.map((json) => ThisOrThatQuestion.fromJson(json)).toList();
  }

  Future<Set<String>> _getSeenQuestionIds(String relationshipId) async {
    final response = await _supabase
        .from('game_questions_seen')
        .select('question_id')
        .eq('relationship_id', relationshipId)
        .eq('game_type', 'this_or_that');

    return response.map((r) => r['question_id'] as String).toSet();
  }

  // ============================================================
  // Answer Submission
  // ============================================================

  Future<void> submitAnswer({
    required String roundId,
    required String userId,
    required String choice, // 'a' or 'b'
    required bool isPartnerA,
  }) async {
    await _supabase.rpc(
      'submit_this_or_that_answer',
      params: {'p_round_id': roundId, 'p_choice': choice},
    );
  }

  Future<bool> prepareNextRound({
    required String sessionId,
    required int roundNumber,
    required String source,
    String? customOwnerId,
  }) async {
    if (source != 'preset' && source != 'custom') {
      throw ArgumentError.value(source, 'source', 'Must be preset or custom');
    }

    final result = await _supabase.rpc(
      'choose_this_or_that_next_question',
      params: {
        'p_session_id': sessionId,
        'p_round_number': roundNumber,
        'p_source': source,
        'p_custom_owner_id': customOwnerId,
      },
    );
    return result == 'preset_fallback';
  }

  // ============================================================
  // Custom Questions CRUD
  // ============================================================

  Future<CustomQuestion> createCustomQuestion({
    required String userId,
    required String questionText,
    required String optionA,
    required String optionB,
    String? emojiA,
    String? emojiB,
    required String tone,
    bool isPrivate = false,
  }) async {
    final response =
        await _supabase
            .from('custom_this_or_that_questions')
            .insert({
              'user_id': userId,
              'question_text': questionText,
              'option_a': optionA,
              'option_b': optionB,
              'emoji_a': emojiA,
              'emoji_b': emojiB,
              'tone': tone,
              'is_private': isPrivate,
            })
            .select()
            .single();

    return CustomQuestion.fromJson(response);
  }

  Future<List<CustomQuestion>> getMyCustomQuestions(String userId) async {
    final response = await _supabase
        .from('custom_this_or_that_questions')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return response.map((json) => CustomQuestion.fromJson(json)).toList();
  }

  Future<void> deleteCustomQuestion(String questionId) async {
    await _supabase
        .from('custom_this_or_that_questions')
        .delete()
        .eq('id', questionId);
  }

  Future<void> updateCustomQuestionPrivacy(
    String questionId,
    bool isPrivate,
  ) async {
    await _supabase
        .from('custom_this_or_that_questions')
        .update({'is_private': isPrivate})
        .eq('id', questionId);
  }

  // ============================================================
  // Session History
  // ============================================================
  Future<List<ThisOrThatSession>> getCompletedSessions(
    String relationshipId,
    String userId, {
    int limit = 20,
    String? cursor,
  }) async {
    // Build the query with all filters first (returns PostgrestFilterBuilder)
    var query = _supabase
        .from('game_sessions')
        .select('*')
        .eq('relationship_id', relationshipId)
        .eq('game_type', 'this_or_that')
        .eq('status', 'completed')
        .not(
          'hidden_by_user_ids',
          'cs',
          jsonEncode([userId]),
        ); // ✅ .not() works on PostgrestFilterBuilder

    // Apply cursor pagination using .lt() (also on PostgrestFilterBuilder)
    if (cursor != null) {
      query = query.lt('created_at', cursor);
    }

    // Now apply ordering and limit (these return PostgrestTransformBuilder)
    final response = await query
        .order('created_at', ascending: false)
        .limit(limit);

    return response.map((json) => ThisOrThatSession.fromJson(json)).toList();
  }

  Future<void> hideSession(String sessionId, String userId) async {
    await _supabase.rpc(
      'hide_this_or_that_session',
      params: {'p_session_id': sessionId},
    );
  }

  Future<void> abandonSession(String sessionId) async {
    await _supabase.rpc(
      'abandon_session_game',
      params: {'p_session_id': sessionId},
    );
  }

  Future<void> advanceSession({
    required String sessionId,
    required int nextRound,
    required int matchCount,
    required int totalRoundsCompleted,
    required bool isCompleted,
  }) async {
    if (!isCompleted) {
      throw StateError(
        'Intermediate rounds advance through question-source selection.',
      );
    }
    await _supabase.rpc(
      'complete_this_or_that_session',
      params: {'p_session_id': sessionId},
    );
  }

  // ============================================================
  // Helper Methods
  // ============================================================

  Future<String> getPartnerId(String relationshipId, String userId) async {
    final response =
        await _supabase
            .from('relationships')
            .select('user_a, user_b')
            .eq('id', relationshipId)
            .single();

    return response['user_a'] == userId
        ? response['user_b']
        : response['user_a'];
  }

  Future<bool> sendReminder(String sessionId, String userId) async {
    final raw = await _supabase.rpc(
      'request_this_or_that_reminder',
      params: {'p_session_id': sessionId},
    );
    final reminder = Map<String, dynamic>.from(raw as Map);
    final playerId = reminder['player_id'] as String?;
    final senderName = reminder['sender_name'] as String? ?? 'Your partner';

    if (playerId != null && playerId.isNotEmpty) {
      await _supabase.functions.invoke(
        'send-notification',
        body: {
          'player_id': playerId,
          'title': 'Your turn in This or That',
          'body': '$senderName is waiting for your pick.',
          'data': {'type': 'game_reminder', 'session_id': sessionId},
        },
      );
    }

    return true;
  }

  ThisOrThatSession _sessionFromRpc(dynamic raw) {
    return ThisOrThatSession.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<String> getPartnerName(String relationshipId, String userId) async {
    final partnerId = await getPartnerId(relationshipId, userId);

    final response =
        await _supabase
            .from('profiles')
            .select('display_name')
            .eq('id', partnerId)
            .single();

    return response['display_name'] as String? ?? 'Partner';
  }

  // Add to ThisOrThatRepository

  Future<void> reportCustomQuestion(String questionId, String reason) async {
    // Single server-side path: records a per-reporter report and hides the
    // question only past the moderation threshold. Replaces the old client
    // insert into a nonexistent forum_reports table + the removed
    // increment_custom_question_report_count RPC (GAMES-1).
    await _supabase.rpc(
      'report_custom_question',
      params: {'p_question_id': questionId, 'p_reason': reason},
    );
  }

  // lib/features/games/this_or_that/data/repositories/this_or_that_repository.dart

  // Add these methods

  // ============================================================
  // Custom Questions CRUD (This or That)
  // ============================================================

  Future<List<CustomThisOrThatQuestion>> getPartnerCustomQuestions(
    String relationshipId,
    String userId,
  ) async {
    final partnerId = await _getPartnerId(relationshipId, userId);

    final response = await _supabase
        .from('custom_this_or_that_questions')
        .select('*')
        .eq('user_id', partnerId)
        .eq('is_private', false)
        .eq('hidden_for_review', false)
        .order('times_used', ascending: true)
        .order('last_used_at', ascending: true, nullsFirst: true);

    return response
        .map((json) => CustomThisOrThatQuestion.fromJson(json))
        .toList();
  }

  // ============================================================
  // Question Selection (updated to use new table)
  // ============================================================

  Future<void> toggleShareToCommunity(String questionId, bool share) async {
    final payload = <String, dynamic>{'shared_to_community': share};
    if (share) {
      payload['community_usage_count'] = 0;
    }

    await _supabase
        .from('custom_this_or_that_questions')
        .update(payload)
        .eq('id', questionId);
  }

  Future<String> _getPartnerId(String relationshipId, String userId) async {
    final response =
        await _supabase
            .from('relationships')
            .select('user_a, user_b')
            .eq('id', relationshipId)
            .single();

    final userA = response['user_a'] as String;
    final userB = response['user_b'] as String;

    return userA == userId ? userB : userA;
  }
}
