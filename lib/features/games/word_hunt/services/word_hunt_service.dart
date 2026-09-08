import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every call this game makes to the server.
///
/// Note what is NOT here: nothing sends a duration. The elapsed time is
/// computed server-side from a timestamp the server wrote, because this
/// game is nothing but a number and a client-supplied number would be
/// the whole game handed to the client.
abstract class WordHuntGateway {
  Future<String> createSession({
    required String relationshipId,
    required String idempotencyKey,
  });

  Future<void> acceptSession(String sessionId);
  Future<void> declineSession(String sessionId);

  /// Starts the clock AND returns the puzzle, in one call, because they
  /// commit in one transaction.
  Future<WordHuntSession> start(String sessionId);

  Future<WordHuntSubmission> submit({
    required String sessionId,
    required List<WordHuntCell> cells,
  });

  Future<WordHuntSession> giveUp(String sessionId);

  Future<WordHuntSession> getState(String sessionId);

  /// The invitation or game already open for this couple, if any.
  Future<WordHuntSession?> getActiveSession(String relationshipId);
}

/// Turns an RPC response into a payload or an error.
///
/// Every RPC in this game answers with a jsonb object rather than an HTTP
/// status, so "did it work" is a field. Lifted out of the service because
/// it is the only real logic there -- everything else is a named call --
/// and a bad unwrap would either swallow an error or throw on a success.
Map<String, dynamic> unwrapWordHuntResponse(Object? response) {
  if (response is! Map) {
    // A null or a scalar means the call did not reach the function we
    // think it did. Failing loudly beats handing the UI an empty session.
    throw const WordHuntApiError(
      code: 'UNKNOWN',
      message: 'Something went wrong. Please try again.',
    );
  }
  final data = Map<String, dynamic>.from(response);
  if (data['error'] == true) throw WordHuntApiError.fromJson(data);
  return data;
}

class WordHuntService implements WordHuntGateway {
  WordHuntService(this._supabase);

  final SupabaseClient _supabase;

  /// Without a bound, a stalled connection leaves a player staring at a
  /// grid whose clock is already running on the server.
  static const _timeout = Duration(seconds: 30);

  Map<String, dynamic> _unwrap(Object? response) =>
      unwrapWordHuntResponse(response);

  @override
  Future<String> createSession({
    required String relationshipId,
    required String idempotencyKey,
  }) async {
    final data = _unwrap(
      await _supabase
          .rpc(
            'word_hunt_create_session',
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
          .rpc('word_hunt_accept_session', params: {'p_session_id': sessionId})
          .timeout(_timeout),
    );
  }

  @override
  Future<void> declineSession(String sessionId) async {
    _unwrap(
      await _supabase
          .rpc('word_hunt_decline_session', params: {'p_session_id': sessionId})
          .timeout(_timeout),
    );
  }

  @override
  Future<WordHuntSession> start(String sessionId) async {
    return WordHuntSession.fromJson(
      _unwrap(
        await _supabase
            .rpc('word_hunt_start', params: {'p_session_id': sessionId})
            .timeout(_timeout),
      ),
    );
  }

  @override
  Future<WordHuntSubmission> submit({
    required String sessionId,
    required List<WordHuntCell> cells,
  }) async {
    final data = _unwrap(
      await _supabase
          .rpc(
            'word_hunt_submit',
            params: {
              'p_session_id': sessionId,
              'p_cells': cells.map((c) => c.toJson()).toList(growable: false),
            },
          )
          .timeout(_timeout),
    );
    return WordHuntSubmission(
      hit: data['hit'] == true,
      session: WordHuntSession.fromJson(data),
    );
  }

  @override
  Future<WordHuntSession> giveUp(String sessionId) async {
    return WordHuntSession.fromJson(
      _unwrap(
        await _supabase
            .rpc('word_hunt_give_up', params: {'p_session_id': sessionId})
            .timeout(_timeout),
      ),
    );
  }

  @override
  Future<WordHuntSession> getState(String sessionId) async {
    return WordHuntSession.fromJson(
      _unwrap(
        await _supabase
            .rpc('get_word_hunt_state', params: {'p_session_id': sessionId})
            .timeout(_timeout),
      ),
    );
  }

  @override
  Future<WordHuntSession?> getActiveSession(String relationshipId) async {
    final data = _unwrap(
      await _supabase
          .rpc(
            'get_active_word_hunt_session',
            params: {'p_relationship_id': relationshipId},
          )
          .timeout(_timeout),
    );
    if (data['session_id'] == null) return null;
    return WordHuntSession.fromJson(data);
  }
}
