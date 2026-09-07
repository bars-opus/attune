import 'package:attune/features/games/snakes_and_ladders/models/snakes_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every call this game makes to the server.
abstract class SnakesGateway {
  Future<String> createSession({
    required String relationshipId,
    required String idempotencyKey,
  });

  Future<void> acceptSession(String sessionId);
  Future<void> declineSession(String sessionId);

  Future<SnakesTurn> rollDie({
    required String sessionId,
    required int roundNumber,
  });

  Future<SnakesSession> getState(String sessionId);

  /// The invitation or game already open for this couple, if any.
  Future<SnakesSession?> getActiveSession(String relationshipId);
}

class SnakesService implements SnakesGateway {
  SnakesService(this._supabase);

  final SupabaseClient _supabase;

  /// Checklist 1.2. Without a bound, a stalled connection leaves the
  /// player watching a die that never lands, with no error and no way
  /// back. Matches the 30s the rest of the app uses.
  static const _timeout = Duration(seconds: 30);

  Map<String, dynamic> _unwrap(Object? response) {
    final data = Map<String, dynamic>.from(response! as Map);
    if (data['error'] == true) throw SnakesApiError.fromJson(data);
    return data;
  }

  @override
  Future<String> createSession({
    required String relationshipId,
    required String idempotencyKey,
  }) async {
    final data = _unwrap(
      await _supabase
          .rpc(
            'snakes_create_session',
            params: {
              'p_relationship_id': relationshipId,
              'p_idempotency_key': idempotencyKey,
            },
          )
          .timeout(_timeout),
    );
    return '${data['session_id']}';
  }

  @override
  Future<void> acceptSession(String sessionId) async {
    _unwrap(
      await _supabase
          .rpc('snakes_accept_session', params: {'p_session_id': sessionId})
          .timeout(_timeout),
    );
  }

  @override
  Future<void> declineSession(String sessionId) async {
    _unwrap(
      await _supabase
          .rpc('snakes_decline_session', params: {'p_session_id': sessionId})
          .timeout(_timeout),
    );
  }

  /// Sends "I am rolling" and nothing else.
  ///
  /// There is deliberately no face-value parameter: the whole content of
  /// a turn is the number the server picks, and a client that could send
  /// one would not be playing a game.
  @override
  Future<SnakesTurn> rollDie({
    required String sessionId,
    required int roundNumber,
  }) async {
    final data = _unwrap(
      await _supabase
          .rpc(
            'snakes_roll_die',
            params: {'p_session_id': sessionId, 'p_round_number': roundNumber},
          )
          .timeout(_timeout),
    );

    return SnakesTurn(
      roundNumber: roundNumber,
      playerId: '${_supabase.auth.currentUser?.id ?? ''}',
      dieRoll: data['die_roll'] as int? ?? 1,
      movedFrom: data['moved_from'] as int? ?? 0,
      rolledTo: data['rolled_to'] as int? ?? 0,
      movedTo: data['moved_to'] as int? ?? 0,
      movement: SnakesMovement.fromWire(data['movement_kind'] as String?),
      didBounce: data['did_bounce'] == true,
    );
  }

  @override
  Future<SnakesSession> getState(String sessionId) async {
    final data = _unwrap(
      await _supabase
          .rpc('get_snakes_session_state', params: {'p_session_id': sessionId})
          .timeout(_timeout),
    );
    return SnakesSession.fromJson(data);
  }

  @override
  Future<SnakesSession?> getActiveSession(String relationshipId) async {
    final data = _unwrap(
      await _supabase
          .rpc(
            'get_active_snakes_session',
            params: {'p_relationship_id': relationshipId},
          )
          .timeout(_timeout),
    );
    if (data['session_id'] == null) return null;
    return SnakesSession.fromJson(data);
  }
}
