import 'package:attune/features/games/snakes_and_ladders/models/snakes_models.dart';
import 'package:attune/features/games/snakes_and_ladders/services/snakes_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local, matching Paint Ball: the games each own their client handle
/// rather than depending on another feature's provider file.
final snakesClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final snakesCurrentUserIdProvider = Provider<String?>(
  (ref) => Supabase.instance.client.auth.currentUser?.id,
);

final snakesGatewayProvider = Provider<SnakesGateway>(
  (ref) => SnakesService(ref.read(snakesClientProvider)),
);

/// What the board is showing right now.
@immutable
class SnakesUiState {
  const SnakesUiState({
    this.session,
    this.isLoading = true,
    this.isRolling = false,
    this.errorMessage,
    this.pendingTurn,
    this.dieFace,
  });

  final SnakesSession? session;
  final bool isLoading;
  final bool isRolling;
  final String? errorMessage;

  /// A turn waiting to be animated -- either the one just rolled, or the
  /// partner's, unwatched, from before this screen opened.
  final SnakesTurn? pendingTurn;

  /// The face the die is showing once it has settled.
  final int? dieFace;

  SnakesUiState copyWith({
    Object? session = _unset,
    bool? isLoading,
    bool? isRolling,
    Object? errorMessage = _unset,
    Object? pendingTurn = _unset,
    Object? dieFace = _unset,
  }) => SnakesUiState(
    session:
        identical(session, _unset) ? this.session : session as SnakesSession?,
    isLoading: isLoading ?? this.isLoading,
    isRolling: isRolling ?? this.isRolling,
    errorMessage:
        identical(errorMessage, _unset)
            ? this.errorMessage
            : errorMessage as String?,
    pendingTurn:
        identical(pendingTurn, _unset)
            ? this.pendingTurn
            : pendingTurn as SnakesTurn?,
    dieFace: identical(dieFace, _unset) ? this.dieFace : dieFace as int?,
  );
}

const Object _unset = Object();

class SnakesNotifier extends StateNotifier<SnakesUiState> {
  SnakesNotifier(this._ref) : super(const SnakesUiState());

  final Ref _ref;
  String? _sessionId;

  /// The last round this client has animated, so a turn is replayed once
  /// and not again on every refresh.
  int _watchedThrough = 0;

  Future<void> load(String sessionId) async {
    // A new game restarts the replay bookkeeping. The provider is global,
    // so without this a second game beginning at round 1 would have its
    // first replay suppressed by the round count of the last one.
    if (_sessionId != sessionId) {
      _watchedThrough = 0;
      state = const SnakesUiState();
    }
    _sessionId = sessionId;
    try {
      final session = await _ref
          .read(snakesGatewayProvider)
          .getState(sessionId);

      // A turn the partner took while this player was away is queued for
      // the replay -- being there when they hit the snake is the entire
      // social content of this game.
      final last = session.lastTurn;
      final unwatched =
          last != null &&
          last.roundNumber > _watchedThrough &&
          last.playerId != _ref.read(snakesCurrentUserIdProvider);

      state = state.copyWith(
        session: session,
        isLoading: false,
        errorMessage: null,
        pendingTurn: unwatched ? last : null,
      );
    } on SnakesApiError catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      // Never surface the raw exception: it can carry row contents
      // (checklist 2.4, 5.5).
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not open this game. Please try again.',
      );
    }
  }

  Future<void> roll() async {
    final session = state.session;
    final sessionId = _sessionId;
    if (session == null || sessionId == null || state.isRolling) return;

    state = state.copyWith(isRolling: true, errorMessage: null);

    try {
      final turn = await _ref
          .read(snakesGatewayProvider)
          .rollDie(sessionId: sessionId, roundNumber: session.currentRound);

      _watchedThrough = turn.roundNumber;

      // Fold the result into the session NOW rather than waiting for the
      // refetch. The animation walks the token to its new cell, and if
      // the session still held the old position the token would snap
      // back for a frame the moment the walk ended.
      final isA = session.userA == _ref.read(snakesCurrentUserIdProvider);
      state = state.copyWith(
        isRolling: false,
        dieFace: turn.dieRoll,
        pendingTurn: turn,
        session: session.copyWith(
          positionA: isA ? turn.movedTo : session.positionA,
          positionB: isA ? session.positionB : turn.movedTo,
        ),
      );
    } on SnakesApiError catch (error) {
      state = state.copyWith(isRolling: false, errorMessage: error.message);
    } catch (_) {
      state = state.copyWith(
        isRolling: false,
        errorMessage: 'Could not roll. Please try again.',
      );
    }
  }

  /// The animation has finished; fold the move into the board and stop
  /// replaying it.
  Future<void> settleTurn() async {
    final turn = state.pendingTurn;
    if (turn == null) return;
    _watchedThrough = turn.roundNumber;
    state = state.copyWith(pendingTurn: null);
    if (_sessionId != null) await load(_sessionId!);
  }

  /// Opens whatever this couple already has, or nothing.
  Future<SnakesSession?> findActive(String relationshipId) async {
    try {
      return await _ref
          .read(snakesGatewayProvider)
          .getActiveSession(relationshipId);
    } on SnakesApiError catch (error) {
      state = state.copyWith(errorMessage: error.message);
      return null;
    } catch (_) {
      state = state.copyWith(
        errorMessage: 'Could not open this game. Please try again.',
      );
      return null;
    }
  }

  Future<String?> createSession(String relationshipId) async {
    try {
      return await _ref
          .read(snakesGatewayProvider)
          .createSession(
            relationshipId: relationshipId,
            // A key per attempt, so a retry after a dropped response
            // resolves to the same session rather than a second one.
            idempotencyKey:
                'snakes-$relationshipId-'
                '${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
          );
    } on SnakesApiError catch (error) {
      state = state.copyWith(errorMessage: error.message);
      return null;
    } catch (_) {
      state = state.copyWith(
        errorMessage: 'Could not start a game. Please try again.',
      );
      return null;
    }
  }

  Future<bool> acceptSession(String sessionId) async {
    try {
      await _ref.read(snakesGatewayProvider).acceptSession(sessionId);
      return true;
    } on SnakesApiError catch (error) {
      state = state.copyWith(errorMessage: error.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        errorMessage: 'Could not join this game. Please try again.',
      );
      return false;
    }
  }

  void clearError() => state = state.copyWith(errorMessage: null);
}

final snakesProvider = StateNotifierProvider<SnakesNotifier, SnakesUiState>(
  SnakesNotifier.new,
);
