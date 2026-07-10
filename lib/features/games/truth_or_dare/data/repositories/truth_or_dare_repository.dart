// lib/features/games/truth_or_dare/data/repositories/truth_or_dare_repository.dart

import 'dart:convert';

import 'package:attune/features/games/data/models/game_session.dart';
import 'package:attune/features/games/truth_or_dare/data/models/custom_truth_or_dare_question.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TruthOrDareRepository {
  final SupabaseClient _supabase;

  TruthOrDareRepository(this._supabase);

  // ============================================================
  // Session Management (reuses Games Module)
  // ============================================================

  Future<GameSession> createSession({
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
            .eq('game_type', 'truth_or_dare')
            .inFilter('status', ['invited', 'active'])
            .maybeSingle();

    if (existingSession != null) {
      return GameSession.fromJson(existingSession);
    }

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
      return GameSession.fromJson(sessionData);
    }

    final response =
        await _supabase
            .from('game_sessions')
            .insert({
              'relationship_id': relationshipId,
              'initiator_id': initiatorId,
              'game_type': 'truth_or_dare',
              'tone': tone,
              'status': 'invited',
              'total_rounds': 10,
              'current_round': 1,
              'intimate_consent_a': tone == 'intimate',
            })
            .select()
            .single();

    await _supabase.from('session_idempotency_keys').insert({
      'key': idempotencyKey,
      'session_id': response['id'],
    });

    return GameSession.fromJson(response);
  }

  Future<GameSession> acceptSession({
    required String sessionId,
    required String userId,
    required bool intimateConsent,
    String? fallbackTone,
  }) async {
    final session =
        await _supabase
            .from('game_sessions')
            .select('*')
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

    return GameSession.fromJson(response);
  }

  Future<GameSession?> getSession(String sessionId) async {
    final response =
        await _supabase
            .from('game_sessions')
            .select('*')
            .eq('id', sessionId)
            .maybeSingle();
    return response == null ? null : GameSession.fromJson(response);
  }

  Future<GameSession?> getActiveSession(String relationshipId) async {
    final response =
        await _supabase
            .from('game_sessions')
            .select('*')
            .eq('relationship_id', relationshipId)
            .eq('game_type', 'truth_or_dare')
            .inFilter('status', ['invited', 'active'])
            .maybeSingle();
    return response == null ? null : GameSession.fromJson(response);
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
    required bool isCompleted,
  }) async {
    await _supabase
        .from('game_sessions')
        .update({
          'current_round': nextRound,
          if (isCompleted) 'status': 'completed',
          if (isCompleted) 'completed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  Future<String?> getRelationshipId(String userId) async {
    final response =
        await _supabase
            .from('relationships')
            .select('id')
            .or('user_a.eq.$userId,user_b.eq.$userId')
            .eq('status', 'active')
            .maybeSingle();
    return response?['id'] as String?;
  }

  Future<String> getPartnerId(String relationshipId, String userId) async {
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

  Future<({String userA, String userB})> getRelationshipMembers(
    String relationshipId,
  ) async {
    final response =
        await _supabase
            .from('relationships')
            .select('user_a, user_b')
            .eq('id', relationshipId)
            .single();

    return (
      userA: response['user_a'] as String,
      userB: response['user_b'] as String,
    );
  }

  // ============================================================
  // Custom Questions CRUD
  // ============================================================

  Future<CustomTruthOrDareQuestion> createCustomQuestion({
    required String userId,
    required String questionType,
    required String content,
    required String tone,
    bool isPrivate = true,
  }) async {
    final response =
        await _supabase
            .from('custom_truth_or_dare_questions')
            .insert({
              'user_id': userId,
              'question_type': questionType,
              'content': content,
              'tone': tone,
              'is_private': isPrivate,
            })
            .select()
            .single();

    return CustomTruthOrDareQuestion.fromJson(response);
  }

  Future<List<CustomTruthOrDareQuestion>> getMyCustomQuestions(
    String userId,
  ) async {
    final response = await _supabase
        .from('custom_truth_or_dare_questions')
        .select('*')
        .eq('user_id', userId)
        .eq('hidden_for_review', false)
        .order('created_at', ascending: false);

    return response
        .map((json) => CustomTruthOrDareQuestion.fromJson(json))
        .toList();
  }

  Future<List<CustomTruthOrDareQuestion>> getPartnerCustomQuestions(
    String relationshipId,
    String userId,
  ) async {
    final partnerId = await getPartnerId(relationshipId, userId);

    final response = await _supabase
        .from('custom_truth_or_dare_questions')
        .select('*')
        .eq('user_id', partnerId)
        .eq('is_private', false)
        .eq('hidden_for_review', false)
        .order('times_used', ascending: true)
        .order('last_used_at', ascending: true, nullsFirst: true);

    return response
        .map((json) => CustomTruthOrDareQuestion.fromJson(json))
        .toList();
  }

  Future<void> updateCustomQuestionPrivacy(
    String questionId,
    bool isPrivate,
  ) async {
    await _supabase
        .from('custom_truth_or_dare_questions')
        .update({'is_private': isPrivate})
        .eq('id', questionId);
  }

  Future<void> deleteCustomQuestion(String questionId) async {
    await _supabase
        .from('custom_truth_or_dare_questions')
        .delete()
        .eq('id', questionId);
  }

  Future<void> reportCustomQuestion(String questionId, String reason) async {
    await _supabase.rpc(
      'report_custom_question',
      params: {'p_question_id': questionId},
    );

    // If content matches safety triggers, handle via safety system
    // This is handled by the safety check service
  }

  // ============================================================
  // Question Selection
  // ============================================================

  Future<Map<String, dynamic>> selectQuestionForRound({
    required String relationshipId,
    required String userId,
    required String tone,
    required String questionType, // 'truth' or 'dare'
    required String sessionId,
  }) async {
    // Step 1: Check custom questions (partner's shared pool)
    final partnerId = await getPartnerId(relationshipId, userId);
    final customResponse = await _supabase
        .from('custom_truth_or_dare_questions')
        .select('*')
        .eq('user_id', partnerId)
        .eq('question_type', questionType)
        .eq('tone', tone)
        .eq('is_private', false)
        .eq('hidden_for_review', false)
        .order('times_used', ascending: true)
        .order('last_used_at', ascending: true, nullsFirst: true)
        .limit(1);

    if (customResponse.isNotEmpty) {
      final custom = customResponse.first;
      // Increment usage count
      await _supabase.rpc(
        'increment_custom_question_usage',
        params: {'p_question_id': custom['id']},
      );
      return {
        'is_custom': true,
        'question_id': custom['id'],
        'question_text': custom['content'],
        'question_type': questionType,
        'custom_question_data': custom,
      };
    }

    // Step 2: Check unseen preset questions
    final seenIds = await _getSeenQuestionIds(relationshipId);
    final presetQuery = _supabase
        .from('game_questions')
        .select('*')
        .eq('game_type', 'truth_or_dare')
        .eq('question_subtype', questionType)
        .eq('tone', tone)
        .eq('active', true);

    final presetResponse = await presetQuery;
    final presetQuestions =
        presetResponse
            .map((json) => json)
            .where((q) => !seenIds.contains(q['id']))
            .toList();

    if (presetQuestions.isNotEmpty) {
      final selected = presetQuestions[0];
      return {
        'is_custom': false,
        'question_id': selected['id'],
        'question_text': selected['question_text'],
        'question_type': questionType,
        'custom_question_data': null,
      };
    }

    // Step 3: Allow repeats from seen pool
    final repeatResponse = await _supabase
        .from('game_questions')
        .select('*')
        .eq('game_type', 'truth_or_dare')
        .eq('question_subtype', questionType)
        .eq('tone', tone)
        .eq('active', true)
        .inFilter('id', seenIds.toList())
        .limit(1);

    if (repeatResponse.isNotEmpty) {
      final selected = repeatResponse.first;
      return {
        'is_custom': false,
        'question_id': selected['id'],
        'question_text': selected['question_text'],
        'question_type': questionType,
        'custom_question_data': null,
      };
    }

    // Fallback: any active question of this type and tone
    final fallbackResponse = await _supabase
        .from('game_questions')
        .select('*')
        .eq('game_type', 'truth_or_dare')
        .eq('question_subtype', questionType)
        .eq('tone', tone)
        .eq('active', true)
        .limit(1);

    if (fallbackResponse.isNotEmpty) {
      final selected = fallbackResponse.first;
      return {
        'is_custom': false,
        'question_id': selected['id'],
        'question_text': selected['question_text'],
        'question_type': questionType,
        'custom_question_data': null,
      };
    }

    throw Exception(
      'No questions available for tone: $tone, type: $questionType',
    );
  }

  Future<TruthOrDareRound> createRoundForTurn({
    required String sessionId,
    required int roundNumber,
    required String activePartnerId,
    required Map<String, dynamic> questionData,
  }) async {
    final response =
        await _supabase
            .from('game_session_rounds')
            .insert({
              'session_id': sessionId,
              'round_number': roundNumber,
              'question_id': questionData['question_id'],
              'active_partner_id': activePartnerId,
              'chosen_type': questionData['question_type'],
              'is_custom': questionData['is_custom'] ?? false,
              'custom_question_data':
                  questionData['custom_question_data'] != null
                      ? jsonEncode(questionData['custom_question_data'])
                      : null,
            })
            .select()
            .single();

    return TruthOrDareRound.fromJson(
      response,
      questionText: questionData['question_text'] as String?,
    );
  }

  Future<List<TruthOrDareRound>> getSessionRounds(String sessionId) async {
    final response =
        await _supabase
            .from('game_session_rounds')
            .select('''
              *,
              game_questions(question_text)
            ''')
            .eq('session_id', sessionId)
            .order('round_number', ascending: true);

    return response.map((json) {
      final nestedQuestion = json['game_questions'];
      String? questionText;
      if (nestedQuestion is Map<String, dynamic>) {
        questionText = nestedQuestion['question_text'] as String?;
      }
      return TruthOrDareRound.fromJson(
        json,
        questionText: questionText,
      );
    }).toList();
  }

  Future<Set<String>> _getSeenQuestionIds(String relationshipId) async {
    final response = await _supabase
        .from('game_questions_seen')
        .select('question_id')
        .eq('relationship_id', relationshipId)
        .eq('game_type', 'truth_or_dare');
    return response.map((r) => r['question_id'] as String).toSet();
  }

  // ============================================================
  // Random Type Selection (50/50)
  // ============================================================

  String selectRandomType() {
    return DateTime.now().millisecondsSinceEpoch % 2 == 0 ? 'truth' : 'dare';
  }

  // ============================================================
  // Skip Mechanic (private — atomic increment)
  // ============================================================

  Future<void> useSkip(String sessionId, String userId, bool isPartnerA) async {
    final field = isPartnerA ? 'skips_used_a' : 'skips_used_b';

    await _supabase.rpc(
      'increment_skip_count',
      params: {
        'p_session_id': sessionId,
        'p_user_id': userId,
        'p_field': field,
      },
    );
  }

  // ============================================================
  // Mark Question as Seen (preset only)
  // ============================================================

  Future<void> markQuestionSeen({
    required String relationshipId,
    required String questionId,
    required bool isCustom,
  }) async {
    if (!isCustom) {
      await _supabase.from('game_questions_seen').upsert({
        'relationship_id': relationshipId,
        'question_id': questionId,
        'game_type': 'truth_or_dare',
      }, onConflict: 'relationship_id,question_id');
    }
  }

  // ============================================================
  // Session History (metadata only)
  // ============================================================

  Future<List<Map<String, dynamic>>> getSessionHistory({
    required String relationshipId,
    required String userId,
    int limit = 20,
    String? cursor,
  }) async {
    final query = _supabase
        .from('game_sessions')
        .select('id, relationship_id, tone, status, created_at, completed_at')
        .eq('relationship_id', relationshipId)
        .eq('game_type', 'truth_or_dare')
        .eq('status', 'completed')
        .not('hidden_by_user_ids', 'cs', jsonEncode([userId]))
        .order('created_at', ascending: false);

    final response = await query;
    final rows = response.cast<Map<String, dynamic>>();
    final enriched = <Map<String, dynamic>>[];

    for (final row in rows) {
      final rounds = await _supabase
          .from('game_session_rounds')
          .select('chosen_type, is_skip')
          .eq('session_id', row['id']);

      final truthsCount =
          rounds.where((round) => round['chosen_type'] == 'truth').length;
      final daresCount =
          rounds.where((round) => round['chosen_type'] == 'dare').length;
      final skipsUsed =
          rounds.where((round) => round['is_skip'] == true).length;

      enriched.add({
        ...row,
        'truths_count': truthsCount,
        'dares_count': daresCount,
        'skips_used': skipsUsed,
      });
    }

    if (cursor == null) {
      return enriched.take(limit).toList();
    }

    final cursorDate = DateTime.parse(cursor);
    return enriched
        .where((row) {
          final createdAt = DateTime.parse(row['created_at'] as String);
          return createdAt.isBefore(cursorDate);
        })
        .take(limit)
        .toList();
  }
}
