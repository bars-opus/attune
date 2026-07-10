// lib/features/games/data/repositories/games_repository.dart

import 'dart:async';
import 'package:attune/features/games/data/models/game_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GamesRepository {
  final SupabaseClient _supabase;

  GamesRepository(this._supabase);

  // ============================================================
  // Session Creation (with idempotency)
  // ============================================================

  Future<GameSession> createSession({
    required String relationshipId,
    required String initiatorId,
    required String gameType,
    required String tone,
    required int totalRounds,
    required bool intimateConsent,
    required String idempotencyKey,
  }) async {
    // Check idempotency first
    final existingKey =
        await _supabase
            .from('session_idempotency_keys')
            .select('session_id')
            .eq('key', idempotencyKey)
            .maybeSingle();

    if (existingKey != null) {
      // Return existing session
      final sessionData =
          await _supabase
              .from('game_sessions')
              .select('*')
              .eq('id', existingKey['session_id'])
              .single();
      return GameSession.fromJson(sessionData);
    }

    // Create new session
    final response =
        await _supabase
            .from('game_sessions')
            .insert({
              'relationship_id': relationshipId,
              'initiator_id': initiatorId,
              'game_type': gameType,
              'tone': tone,
              'status': 'invited',
              'total_rounds': totalRounds,
              'intimate_consent_a': intimateConsent,
              'intimate_consent_b': false,
            })
            .select()
            .single();

    // Store idempotency key
    await _supabase.from('session_idempotency_keys').insert({
      'key': idempotencyKey,
      'session_id': response['id'],
    });

    return GameSession.fromJson(response);
  }

  // ============================================================
  // Session Acceptance
  // ============================================================

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
              'intimate_consent_b': intimateConsentB,
              'started_at': DateTime.now().toIso8601String(),
            })
            .eq('id', sessionId)
            .select()
            .single();

    return GameSession.fromJson(response);
  }

  // ============================================================
  // Submit Answer (with concurrency control)
  // ============================================================

  Future<void> submitAnswer({
    required String roundId,
    required String userId,
    required String answer, // 'a' or 'b' for This or That, or text for others
    required bool isPartnerA,
  }) async {
    final field = isPartnerA ? 'answer_a' : 'answer_b';
    final submittedAtField =
        isPartnerA ? 'answer_a_submitted_at' : 'answer_b_submitted_at';

    // Update the round with answer
    await _supabase
        .from('game_session_rounds')
        .update({
          field: answer,
          submittedAtField: DateTime.now().toIso8601String(),
        })
        .eq('id', roundId);

    // Check if both have answered
    final round =
        await _supabase
            .from('game_session_rounds')
            .select('answer_a, answer_b, both_answered')
            .eq('id', roundId)
            .single();

    final bothAnswered = round['answer_a'] != null && round['answer_b'] != null;

    if (bothAnswered && !(round['both_answered'] as bool)) {
      // Use transaction with row lock to prevent double reveal
      await _supabase.rpc(
        'mark_round_complete',
        params: {'p_round_id': roundId},
      );
    }
  }

  // ============================================================
  // Get Active Session
  // ============================================================

  Future<GameSession?> getActiveSession({
    required String relationshipId,
    required String gameType,
  }) async {
    final response =
        await _supabase
            .from('game_sessions')
            .select('*')
            .eq('relationship_id', relationshipId)
            .eq('game_type', gameType)
            .inFilter('status', ['invited', 'active'])
            .maybeSingle();

    return response != null ? GameSession.fromJson(response) : null;
  }

  // ============================================================
  // Get Session Rounds
  // ============================================================

  Future<List<GameRound>> getSessionRounds(String sessionId) async {
    final response = await _supabase
        .from('game_session_rounds')
        .select('*')
        .eq('session_id', sessionId)
        .order('round_number', ascending: true);

    return response.map((json) => GameRound.fromJson(json)).toList();
  }

  // ============================================================
  // Send Reminder (rate limited)
  // ============================================================

  Future<bool> sendReminder(String sessionId, String userId) async {
    // Check rate limit
    final session =
        await _supabase
            .from('game_sessions')
            .select('remind_last_sent_at')
            .eq('id', sessionId)
            .single();

    final lastSent =
        session['remind_last_sent_at'] != null
            ? DateTime.parse(session['remind_last_sent_at'])
            : null;

    if (lastSent != null && DateTime.now().difference(lastSent).inHours < 4) {
      throw Exception('RATE_LIMITED');
    }

    // Update last sent time
    await _supabase
        .from('game_sessions')
        .update({'remind_last_sent_at': DateTime.now().toIso8601String()})
        .eq('id', sessionId);

    return true;
  }

  // ============================================================
  // Abandon Session
  // ============================================================

  Future<void> abandonSession(String sessionId) async {
    await _supabase
        .from('game_sessions')
        .update({
          'status': 'abandoned',
          'abandoned_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  // ============================================================
  // Hide Session (soft delete from user's view)
  // ============================================================

  Future<void> hideSession(String sessionId, String userId) async {
    final session =
        await _supabase
            .from('game_sessions')
            .select('hidden_by_user_ids')
            .eq('id', sessionId)
            .single();

    final hiddenIds = session['hidden_by_user_ids'] as List? ?? [];
    if (!hiddenIds.contains(userId)) {
      hiddenIds.add(userId);
      await _supabase
          .from('game_sessions')
          .update({'hidden_by_user_ids': hiddenIds})
          .eq('id', sessionId);
    }
  }


}
