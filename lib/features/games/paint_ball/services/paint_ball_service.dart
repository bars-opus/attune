// lib/features/games/paint_ball/services/paint_ball_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/paint_ball_models.dart';

abstract class PaintBallGateway {
  Future<PaintBallCreateSessionResponse> createSession({
    required String relationshipId,
    String tone = 'playful',
    String? idempotencyKey,
    bool allowPartnerAuthored = false,
  });

  Future<void> acceptSession(String sessionId);
  Future<void> declineSession(String sessionId);

  Future<PaintBallShotResult> takeTurn({
    required String sessionId,
    required int roundNumber,
    required int hidePosition,
    required int shotPosition,
  });

  Future<void> resolvePenalty({
    required String sessionId,
    required String outcome,
  });

  Future<PaintBallSessionState> getSessionState(String sessionId);
  Future<PaintBallSessionState?> getActiveSession(String relationshipId);

  Future<PaintBallHistoryPage> getHistory({
    required String relationshipId,
    int limit = 20,
    String? cursor,
  });

  Future<void> hideSession(String sessionId);

  RealtimeChannel subscribeToSession(
    String sessionId, {
    required void Function(Map<String, dynamic> payload) onUpdate,
  });
}

class PaintBallService implements PaintBallGateway {
  final SupabaseClient _supabase;

  PaintBallService(this._supabase);

  // ============================================================
  // Create Session
  // ============================================================
  @override
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
  @override
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
  @override
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
  @override
  Future<PaintBallShotResult> takeTurn({
    required String sessionId,
    required int roundNumber,
    required int hidePosition,
    required int shotPosition,
  }) async {
    final params = {
      'p_session_id': sessionId,
      'p_round_number': roundNumber,
      'p_hide_position': hidePosition,
      'p_shot_position': shotPosition,
    };

    // The round number is the idempotency key, so retrying the exact same
    // request cannot spend another turn or remove another life. Three bounded
    // retries cover a brief handoff between Wi-Fi and mobile data while still
    // surfacing a persistent error instead of spinning forever.
    Object? response;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        response = await _supabase.rpc('paint_ball_take_turn', params: params);
        break;
      } catch (_) {
        if (attempt == 3) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }
    return PaintBallShotResult.fromJson(data);
  }

  // ============================================================
  // Resolve Penalty
  // ============================================================
  @override
  Future<void> resolvePenalty({
    required String sessionId,
    required String outcome, // 'completed' or 'declined'
  }) async {
    final response = await _supabase.rpc(
      'paint_ball_resolve_penalty',
      params: {'p_session_id': sessionId, 'p_outcome': outcome},
    );

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }
  }

  // ============================================================
  // Get Session State
  // ============================================================
  @override
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
  @override
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

  @override
  Future<PaintBallHistoryPage> getHistory({
    required String relationshipId,
    int limit = 20,
    String? cursor,
  }) async {
    final response = await _supabase.rpc(
      'get_paint_ball_history',
      params: {
        'p_relationship_id': relationshipId,
        'p_limit': limit,
        'p_cursor': cursor,
      },
    );

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }
    return PaintBallHistoryPage.fromJson(data);
  }

  @override
  Future<void> hideSession(String sessionId) async {
    final response = await _supabase.rpc(
      'paint_ball_hide_session',
      params: {'p_session_id': sessionId},
    );

    final data = Map<String, dynamic>.from(response as Map);
    if (data['error'] == true) {
      throw PaintBallApiError.fromJson(data);
    }
  }

  // ============================================================
  // Stream Session Updates (Realtime)
  // ============================================================
  @override
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
