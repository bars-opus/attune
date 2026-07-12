// lib/features/games/this_or_that/data/repositories/this_or_that_repository.dart

import 'dart:convert';
import 'package:attune/features/games/this_or_that/data/models/custom_question.dart';
import 'package:attune/features/games/this_or_that/data/models/custom_this_or_that_question.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
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
    final existingSession =
        await _supabase
            .from('game_sessions')
            .select('*')
            .eq('relationship_id', relationshipId)
            .eq('game_type', 'this_or_that')
            .inFilter('status', ['invited', 'active'])
            .maybeSingle();

    if (existingSession != null) {
      return ThisOrThatSession.fromJson(existingSession);
    }

    // Check idempotency
    final existingKey =
        await _supabase
            .from('session_idempotency_keys')
            .select('session_id')
            .eq('key', idempotencyKey)
            .maybeSingle();

    if (existingKey != null) {
      final sessionData =
          await _supabase
              .from('game_sessions')
              .select('*')
              .eq('id', existingKey['session_id'])
              .single();
      return ThisOrThatSession.fromJson(sessionData);
    }

    final response =
        await _supabase
            .from('game_sessions')
            .insert({
              'relationship_id': relationshipId,
              'initiator_id': initiatorId,
              'game_type': 'this_or_that',
              'tone': tone,
              'status': 'invited',
              'total_rounds': 10,
              'intimate_consent_a': tone == 'intimate',
            })
            .select()
            .single();

    await _supabase.from('session_idempotency_keys').insert({
      'key': idempotencyKey,
      'session_id': response['id'],
    });

    return ThisOrThatSession.fromJson(response);
  }

  Future<ThisOrThatSession> acceptSession({
    required String sessionId,
    required String userId,
    required bool intimateConsent,
    String? fallbackTone,
  }) async {
    final session =
        await _supabase
            .from('game_sessions')
            .select('tone')
            .eq('id', sessionId)
            .single();

    final tone = fallbackTone ?? session['tone'];
    final intimateConsentB =
        session['tone'] == 'intimate' ? intimateConsent : false;

    final response =
        await _supabase
            .from('game_sessions')
            .update({
              'status': 'active',
              'tone': tone,
              'current_round': 1,
              'intimate_consent_b': intimateConsentB,
              'started_at': DateTime.now().toIso8601String(),
            })
            .eq('id', sessionId)
            .select()
            .single();

    // Generate and insert 10 rounds
    await _generateRounds(sessionId, tone, response['relationship_id']);

    return ThisOrThatSession.fromJson(response);
  }

  Future<void> _generateRounds(
    String sessionId,
    String tone,
    String relationshipId,
  ) async {
    // Get custom questions first
    final customQuestions = await getAvailableCustomQuestions(
      relationshipId,
      tone,
    );
    // Get preset questions
    final presetQuestions = await getUnseenPresetQuestions(
      relationshipId,
      tone,
    );

    // Select up to 3 custom questions, fill rest with preset
    final selectedCustom = (customQuestions..shuffle()).take(3).toList();
    final selectedPreset =
        (presetQuestions..shuffle()).take(10 - selectedCustom.length).toList();

    final allQuestions = [...selectedCustom, ...selectedPreset];
    allQuestions.shuffle();

    for (int i = 0; i < allQuestions.length; i++) {
      final q = allQuestions[i];
      await _supabase.from('game_session_rounds').insert({
        'session_id': sessionId,
        'round_number': i + 1,
        'question_id': q.id,
        'is_custom': q is CustomQuestion,
        'custom_question_data':
            q is CustomQuestion
                ? jsonEncode({
                  'question_text': q.questionText,
                  'option_a': q.optionA,
                  'option_b': q.optionB,
                  'emoji_a': q.emojiA,
                  'emoji_b': q.emojiB,
                })
                : null,
      });
    }
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
    final field = isPartnerA ? 'answer_a' : 'answer_b';
    final submittedAtField =
        isPartnerA ? 'answer_a_submitted_at' : 'answer_b_submitted_at';

    await _supabase
        .from('game_session_rounds')
        .update({
          field: choice,
          submittedAtField: DateTime.now().toIso8601String(),
        })
        .eq('id', roundId);

    // Check if both answered
    final round =
        await _supabase
            .from('game_session_rounds')
            .select('answer_a, answer_b, both_answered, session_id')
            .eq('id', roundId)
            .single();

    final bothAnswered = round['answer_a'] != null && round['answer_b'] != null;

    if (bothAnswered && !(round['both_answered'] as bool)) {
      await _supabase.rpc(
        'mark_this_or_that_round_complete',
        params: {'p_round_id': roundId},
      );
    }
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
    final response =
        await _supabase
            .from('game_sessions')
            .select('hidden_by_user_ids')
            .eq('id', sessionId)
            .single();

    final hiddenByUserIds =
        response['hidden_by_user_ids'] != null
            ? List<String>.from(response['hidden_by_user_ids'] as List)
            : <String>[];

    if (!hiddenByUserIds.contains(userId)) {
      hiddenByUserIds.add(userId);
      await _supabase
          .from('game_sessions')
          .update({'hidden_by_user_ids': hiddenByUserIds})
          .eq('id', sessionId);
    }
  }

  Future<void> abandonSession(String sessionId) async {
    await _supabase
        .from('game_sessions')
        .update({
          'status': 'abandoned',
          'abandoned_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  Future<void> advanceSession({
    required String sessionId,
    required int nextRound,
    required int matchCount,
    required int totalRoundsCompleted,
    required bool isCompleted,
  }) async {
    await _supabase
        .from('game_sessions')
        .update({
          'current_round': nextRound,
          'match_count': matchCount,
          'total_rounds_completed': totalRoundsCompleted,
          if (isCompleted) 'status': 'completed',
          if (isCompleted) 'completed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
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
    // First, get the session to find the partner's ID
    final session =
        await _supabase
            .from('game_sessions')
            .select('relationship_id, initiator_id')
            .eq('id', sessionId)
            .single();

    final relationshipId = session['relationship_id'] as String;
    final initiatorId = session['initiator_id'] as String;

    // Determine who is the partner (the one who hasn't answered yet)
    final partnerId =
        initiatorId == userId
            ? await getPartnerId(relationshipId, userId)
            : initiatorId;

    // Check rate limit
    final sessionWithRemind =
        await _supabase
            .from('game_sessions')
            .select('remind_last_sent_at')
            .eq('id', sessionId)
            .single();

    final lastSent =
        sessionWithRemind['remind_last_sent_at'] != null
            ? DateTime.parse(sessionWithRemind['remind_last_sent_at'])
            : null;

    if (lastSent != null && DateTime.now().difference(lastSent).inHours < 4) {
      throw Exception('RATE_LIMITED');
    }

    // Update last sent time
    await _supabase
        .from('game_sessions')
        .update({'remind_last_sent_at': DateTime.now().toIso8601String()})
        .eq('id', sessionId);

    // Get partner's push notification player ID
    final partnerProfile =
        await _supabase
            .from('profiles')
            .select('onesignal_player_id, display_name')
            .eq('id', partnerId)
            .single();

    final playerId = partnerProfile['onesignal_player_id'] as String?;
    final partnerName = partnerProfile['display_name'] as String? ?? 'Partner';

    // Send push notification via OneSignal
    if (playerId != null && playerId.isNotEmpty) {
      // Call your notification service
      await _supabase.functions.invoke(
        'send-notification',
        body: {
          'player_id': playerId,
          'title': 'Your turn in This or That',
          'body': '$partnerName is waiting for you to answer.',
          'data': {'type': 'game_reminder', 'session_id': sessionId},
        },
      );
    }

    return true;
  }

  Stream<GameRound> watchRound(String roundId) {
    return _supabase
        .from('game_session_rounds')
        .stream(primaryKey: ['id'])
        .eq('id', roundId)
        .map((event) {
          // The stream returns a list, take the first item
          final data = event.first;
          return GameRound.fromJson(data);
        });
  }

  // Add to ThisOrThatRepository

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

  Future<List<dynamic>> selectQuestionsForSession({
    required String relationshipId,
    required String tone,
    required int count,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final partnerId = await _getPartnerId(relationshipId, userId);
    final seenIds = await _getSeenQuestionIds(relationshipId);

    // Step 1: Get custom questions (shared, not private)
    final customQuestions = await _supabase
        .from('custom_this_or_that_questions')
        .select('*')
        .or('user_id.eq.$userId,user_id.eq.$partnerId')
        .eq('is_private', false)
        .eq('hidden_for_review', false)
        .eq('tone', tone)
        .order('times_used', ascending: true)
        .order('last_used_at', ascending: true, nullsFirst: true)
        .limit(3); // Max 3 custom questions per session

    // Step 2: Get unseen preset questions
    final presetQuery = _supabase
        .from('game_questions')
        .select('*')
        .eq('game_type', 'this_or_that')
        .eq('active', true)
        .eq('tone', tone);

    final presetResponse = await presetQuery;
    var presetQuestions =
        presetResponse
            .map((json) => ThisOrThatQuestion.fromJson(json))
            .where((q) => !seenIds.contains(q.id))
            .toList();

    // Intimate tone guarantee
    if (tone == 'intimate') {
      final intimateQuestions =
          presetQuestions.where((q) => q.toneLevel == 4).toList();
      final spicyQuestions =
          presetQuestions.where((q) => q.toneLevel == 3).toList();
      if (intimateQuestions.length >= 5) {
        presetQuestions = intimateQuestions;
      } else if (intimateQuestions.length + spicyQuestions.length >= 5) {
        presetQuestions = [...intimateQuestions, ...spicyQuestions];
      }
    }

    // Step 3: Combine: custom first, then preset
    final List<dynamic> selected = [];
    final customList =
        customQuestions
            .map((q) => CustomThisOrThatQuestion.fromJson(q))
            .toList();
    selected.addAll(customList);

    // Fill remaining slots with preset questions
    final remaining = count - selected.length;
    final shuffledPreset =
        (presetQuestions..shuffle()).take(remaining).toList();
    selected.addAll(shuffledPreset);

    return selected;
  }

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
