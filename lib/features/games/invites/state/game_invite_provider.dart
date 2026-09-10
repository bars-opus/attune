import 'package:attune/features/games/invites/services/game_invite_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Every game that can be invited -- which is now all of them.
///
/// Must match game_invite_type_allowed in the migrations: the server
/// refuses anything else, and a game staged here that the server will
/// not create is a Send that always fails. A test parses the SQL and
/// compares, so the two cannot drift.
///
/// The RPC gives each game the session shape it expects (a round count,
/// a tone, a journey and chapter for 36 Questions) and the games build
/// the rest on first open. Love Map is the exception it makes: it is
/// sessionless by design, so its invitation opens already active -- the
/// card points at prompts both partners already share.
const kInvitableGameTypes = {
  'this_or_that',
  'truth_or_dare',
  '36_questions',
  'mirror',
  'sliding_scale',
  'scenario',
  'love_map',
  'paint_ball',
  'snakes_and_ladders',
  'word_hunt',
};

final gameInviteClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final gameInviteGatewayProvider = Provider<GameInviteGateway>(
  (ref) => GameInviteService(ref.read(gameInviteClientProvider)),
);

/// The game staged in the composer, if any.
///
/// Picking a game from the sheet does NOT create anything: it puts the
/// game here, the composer renders it where the text field was, and only
/// Send reaches the server. That ordering is the point of the feature --
/// backing out of a game you did not send must leave no trace, and the
/// old flow created the session on selection, so a glance at the
/// catalogue posted a card.
@immutable
class GameComposerState {
  const GameComposerState({
    this.gameType,
    this.sending = false,
    this.errorMessage,
  });

  /// The game waiting to be sent. Null when the composer is a text field.
  final String? gameType;
  final bool sending;
  final String? errorMessage;

  bool get isStaged => gameType != null;

  GameComposerState copyWith({
    String? gameType,
    bool? sending,
    String? errorMessage,
    bool clearGame = false,
    bool clearError = false,
  }) => GameComposerState(
    gameType: clearGame ? null : (gameType ?? this.gameType),
    sending: sending ?? this.sending,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

class GameComposerNotifier extends StateNotifier<GameComposerState> {
  GameComposerNotifier(this._ref, this.relationshipId)
    : super(const GameComposerState());

  final Ref _ref;

  /// Whose conversation this composer belongs to.
  ///
  /// The composer is per-relationship, not global. A single instance let
  /// a game staged while looking at one partner appear in the next
  /// conversation opened -- and Send would then have invited the wrong
  /// person, because the relationship id comes from the screen rather
  /// than from the staged game.
  final String relationshipId;

  /// The idempotency key for the game currently staged.
  ///
  /// Held across retries and retired only when a create returns
  /// (checklist 1.1, 2.18). A send whose response was dropped may well
  /// have created the invitation; a fresh key on the second tap would
  /// post a second card for a player who thinks they sent one.
  String? _sendKey;
  String? _keyGameType;

  /// Stages a game for sending. Replaces whatever was staged before.
  void stage(String gameType) {
    if (state.gameType != gameType) _resetKey();
    state = GameComposerState(gameType: gameType);
  }

  /// Clears the composer without sending anything.
  void cancel() {
    _resetKey();
    state = const GameComposerState();
  }

  void _resetKey() {
    _sendKey = null;
    _keyGameType = null;
  }

  /// Sends the staged invitation.
  ///
  /// Returns the session id on success, null on failure -- with the
  /// reason left in [state.errorMessage] and the game still staged, so
  /// the player can retry rather than having to find the game again.
  Future<String?> send() async {
    final gameType = state.gameType;
    if (gameType == null || state.sending) return null;

    state = state.copyWith(sending: true, clearError: true);

    // A key belongs to one game: staging a different game must not
    // inherit the last one's key, or the server would hand back the
    // previous game (or refuse the mismatch).
    if (_sendKey == null || _keyGameType != gameType) {
      _sendKey = 'game_invite:$relationshipId:$gameType:${const Uuid().v4()}';
      _keyGameType = gameType;
    }

    try {
      final invite = await _ref
          .read(gameInviteGatewayProvider)
          .create(
            relationshipId: relationshipId,
            gameType: gameType,
            idempotencyKey: _sendKey!,
          );
      if (!mounted) return invite.sessionId;
      _resetKey();
      state = const GameComposerState();
      return invite.sessionId;
    } on GameInviteApiError catch (error) {
      if (!mounted) return null;
      // The key is deliberately KEPT: this failure may have been a lost
      // response rather than a refusal, and the retry must be the same
      // request.
      state = state.copyWith(sending: false, errorMessage: error.message);
      return null;
    } catch (_) {
      if (!mounted) return null;
      // Never surface the raw exception: it can carry connection
      // details and row contents (checklist 2.4, 5.5).
      state = state.copyWith(
        sending: false,
        errorMessage: 'Could not send. Check your connection.',
      );
      return null;
    }
  }
}

/// The composer for one conversation, keyed by relationship.
final gameComposerProvider = StateNotifierProvider.family<
  GameComposerNotifier,
  GameComposerState,
  String
>(GameComposerNotifier.new);
