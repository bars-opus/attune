import 'package:supabase_flutter/supabase_flutter.dart';

/// A refusal from the invite RPCs, carrying the sentence the server chose.
///
/// The code stays internal (checklist 5.5): it exists so the client can
/// branch, never so it can be shown. [message] is the only part meant for
/// a person, and the server writes it precisely so this layer is not
/// inventing copy for conditions it cannot see.
class GameInviteApiError implements Exception {
  const GameInviteApiError({required this.code, required this.message});

  factory GameInviteApiError.fromJson(Map<String, dynamic> json) =>
      GameInviteApiError(
        code: '${json['code'] ?? 'UNKNOWN'}',
        message:
            '${json['message'] ?? 'Something went wrong. Please try again.'}',
      );

  final String code;
  final String message;

  @override
  String toString() => 'GameInviteApiError($code)';
}

/// Asking someone to play, for every game.
///
/// One gateway rather than ten. The games differ enormously once they
/// start; the invitation is identical in all of them -- a session row
/// whose creation posts a card into the conversation.
abstract class GameInviteGateway {
  /// Creates the invitation, or returns the one already open.
  ///
  /// [idempotencyKey] MUST be held across retries of the same intent
  /// (checklist 1.1, 2.18): a create whose response was lost may well
  /// have succeeded, and a fresh key would invite twice.
  Future<GameInvite> create({
    required String relationshipId,
    required String gameType,
    required String idempotencyKey,
  });

  Future<void> accept(String sessionId);

  /// Declines, or -- for the player who sent it -- cancels.
  Future<void> decline(String sessionId);
}

/// The result of asking for an invitation.
class GameInvite {
  const GameInvite({required this.sessionId, required this.existing});

  final String sessionId;

  /// True when the server handed back a game that already existed: a
  /// retry of this same create, or the couple's open game of this kind.
  /// The caller uses it to tell "invitation sent" from "here is the one
  /// you already have".
  final bool existing;
}

class GameInviteService implements GameInviteGateway {
  GameInviteService(this._supabase);

  final SupabaseClient _supabase;

  /// Checklist 1.2. Without a bound, a stalled connection leaves the
  /// player looking at a send button that never resolves.
  static const _timeout = Duration(seconds: 30);

  Map<String, dynamic> _unwrap(Object? response) {
    final data = Map<String, dynamic>.from(response! as Map);
    if (data['error'] == true) throw GameInviteApiError.fromJson(data);
    return data;
  }

  @override
  Future<GameInvite> create({
    required String relationshipId,
    required String gameType,
    required String idempotencyKey,
  }) async {
    final data = _unwrap(
      await _supabase
          .rpc(
            'game_invite_create',
            params: {
              'p_relationship_id': relationshipId,
              'p_game_type': gameType,
              'p_idempotency_key': idempotencyKey,
            },
          )
          .timeout(_timeout),
    );
    return GameInvite(
      sessionId: '${data['session_id']}',
      existing: data['existing'] == true,
    );
  }

  @override
  Future<void> accept(String sessionId) async {
    _unwrap(
      await _supabase
          .rpc('game_invite_accept', params: {'p_session_id': sessionId})
          .timeout(_timeout),
    );
  }

  @override
  Future<void> decline(String sessionId) async {
    _unwrap(
      await _supabase
          .rpc('game_invite_decline', params: {'p_session_id': sessionId})
          .timeout(_timeout),
    );
  }
}
