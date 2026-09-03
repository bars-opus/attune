// lib/features/games/paint_ball/services/paint_ball_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
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
        // Generated when the caller does not supply one.
        // session_idempotency_keys.key is NOT NULL, and no caller in the
        // app has ever passed a key -- the parameter existed at every
        // level of the chain and nothing filled it -- so creating a Paint
        // Ball always failed on the constraint.
        //
        // A fresh key per call still buys the guard it exists for: the
        // RPC returns the existing session on a repeat, so a retry that
        // reuses this key cannot create a second game.
        'p_idempotency_key': idempotencyKey ?? const Uuid().v4(),
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
  /// One turn: hide somewhere, and shoot where you think they are.
  ///
  /// The server compares the shot to where the partner actually hid, so
  /// a client cannot report a hit it did not earn -- and the skill becomes
  /// predicting your partner rather than reacting to a sweep.
  Future<PaintBallShotResult> takeTurn({
    required String sessionId,
    required int roundNumber,
    required int hidePosition,
    required int shotPosition,
  }) async {
    final response = await _supabase.rpc(
      'paint_ball_take_turn',
      params: {
        'p_session_id': sessionId,
        'p_round_number': roundNumber,
        'p_hide_position': hidePosition,
        'p_shot_position': shotPosition,
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
