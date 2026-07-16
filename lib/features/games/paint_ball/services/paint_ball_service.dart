// lib/features/games/paint_ball/services/paint_ball_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/paint_ball_models.dart';

class PaintBallService {
  final SupabaseClient _supabase;

  PaintBallService(this._supabase);

  // ============================================================
  // Create Session
  // ============================================================
  Future<PaintBallCreateSessionResponse> createSession({
    required String relationshipId,
    String tone = 'playful',
    String? idempotencyKey,
    bool allowPartnerAuthored = false,
  }) async {
    final response = await _supabase.rpc(
      'paint_ball_create_session',
      params: {
        'p_relationship_id': relationshipId,
        'p_tone': tone,
        'p_idempotency_key': idempotencyKey,
        'p_allow_partner_authored': allowPartnerAuthored,
      },
    );

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }

    return PaintBallCreateSessionResponse.fromJson(data);
  }

  // ============================================================
  // Accept Session
  // ============================================================
  Future<void> acceptSession(String sessionId) async {
    final response = await _supabase.rpc(
      'paint_ball_accept_session',
      params: {'p_session_id': sessionId},
    );

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }
  }

  // ============================================================
  // Decline Session
  // ============================================================
  Future<void> declineSession(String sessionId) async {
    final response = await _supabase.rpc(
      'paint_ball_decline_session',
      params: {'p_session_id': sessionId},
    );

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }
  }

  // ============================================================
  // Fire Shot
  // ============================================================
  Future<PaintBallShotResult> fireShot({
    required String sessionId,
    required int roundNumber,
    required bool hit,
    String? idempotencyKey,
  }) async {
    final response = await _supabase.rpc(
      'paint_ball_fire_shot',
      params: {
        'p_session_id': sessionId,
        'p_round_number': roundNumber,
        'p_hit': hit,
        'p_idempotency_key': idempotencyKey,
      },
    );

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }

    return PaintBallShotResult.fromJson(data);
  }

  // ============================================================
  // Resolve Penalty
  // ============================================================
  Future<void> resolvePenalty({
    required String sessionId,
    required String outcome, // 'completed' or 'declined'
  }) async {
    final response = await _supabase.rpc(
      'paint_ball_resolve_penalty',
      params: {
        'p_session_id': sessionId,
        'p_outcome': outcome,
      },
    );

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }
  }

  // ============================================================
  // Get Session State
  // ============================================================
  Future<PaintBallSessionState> getSessionState(String sessionId) async {
    final response = await _supabase.rpc(
      'get_paint_ball_session_state',
      params: {'p_session_id': sessionId},
    );

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }

    return PaintBallSessionState.fromJson(data);
  }

  // ============================================================
  // Find Active Session for Relationship
  // Returns null when the couple has no resumable Paint Ball session.
  // ============================================================
  Future<PaintBallSessionState?> getActiveSession(String relationshipId) async {
    final response = await _supabase.rpc(
      'get_active_paint_ball_session',
      params: {'p_relationship_id': relationshipId},
    );

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }

    final session = data['session'];
    if (session == null) return null;
    return PaintBallSessionState.fromJson(Map<String, dynamic>.from(session));
  }

  // ============================================================
  // Stream Session Updates (Realtime)
  // ============================================================
  RealtimeChannel subscribeToSession(
    String sessionId, {
    required void Function(Map<String, dynamic> payload) onUpdate,
  }) {
    return _supabase
        .channel('paint_ball_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'game_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: sessionId,
          ),
          callback: (payload) {
            onUpdate(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .subscribe();
  }
}
