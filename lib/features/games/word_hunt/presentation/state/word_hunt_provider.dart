import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/services/word_hunt_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Local, matching Paint Ball and Snakes: each game owns its client
/// handle rather than depending on another feature's provider file.
final wordHuntClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final wordHuntCurrentUserIdProvider = Provider<String?>(
  (ref) => Supabase.instance.client.auth.currentUser?.id,
);

final wordHuntGatewayProvider = Provider<WordHuntGateway>(
  (ref) => WordHuntService(ref.read(wordHuntClientProvider)),
);

@immutable
class WordHuntUiState {
  const WordHuntUiState({
    this.session,
    this.isLoading = true,
    this.isSubmitting = false,
    this.errorMessage,
    this.missCells,
    this.missNonce = 0,
  });

  final WordHuntSession? session;
  final bool isLoading;

  /// A submission is in flight. The board goes inert rather than letting
  /// a second drag start, which would race the first.
  final bool isSubmitting;

  final String? errorMessage;

  /// The cells of the guess the server just rejected, so the board can
  /// animate that pill off. Paired with a nonce because the SAME wrong
  /// guess made twice must still animate twice.
  final List<WordHuntCell>? missCells;
  final int missNonce;

  WordHuntUiState copyWith({
    Object? session = _unset,
    bool? isLoading,
    bool? isSubmitting,
    Object? errorMessage = _unset,
    Object? missCells = _unset,
    int? missNonce,
  }) => WordHuntUiState(
    session:
        identical(session, _unset) ? this.session : session as WordHuntSession?,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    errorMessage:
        identical(errorMessage, _unset)
            ? this.errorMessage
            : errorMessage as String?,
    missCells:
        identical(missCells, _unset)
            ? this.missCells
            : missCells as List<WordHuntCell>?,
    missNonce: missNonce ?? this.missNonce,
  );

  static const _unset = Object();
}

class WordHuntNotifier extends StateNotifier<WordHuntUiState> {
  WordHuntNotifier(this._ref, this.sessionId) : super(const WordHuntUiState()) {
    refresh();
  }

  final Ref _ref;
  final String sessionId;

  /// THE DISPLAY CLOCK.
  ///
  /// The running number on screen is an estimate, and is labelled as one
  /// in the code because it is easy to forget: the value that counts is
  /// computed server-side and replaces this the moment the attempt ends.
  ///
  /// Seeded from (server_observed_at - started_at) and advanced by a
  /// monotonic Stopwatch, never by the device wall clock -- a phone whose
  /// clock is wrong, or which changes timezone mid-game, must not make
  /// the timer jump. Reseeded on every state refetch.
  final Stopwatch _stopwatch = Stopwatch();
  Duration _seed = Duration.zero;

  /// The estimated elapsed time to show right now.
  Duration get displayElapsed => _seed + _stopwatch.elapsed;

  void _reseedClock(WordHuntSession session) {
    final startedAt = session.myStartedAt;
    if (startedAt == null || session.myStatus.isTerminal) {
      _stopwatch.stop();
      _stopwatch.reset();
      _seed = Duration.zero;
      return;
    }
    var elapsed = session.serverObservedAt.difference(startedAt);
    if (elapsed.isNegative) elapsed = Duration.zero;
    _seed = elapsed;
    _stopwatch
      ..reset()
      ..start();
  }

  Future<void> refresh() async {
    try {
      final session = await _ref
          .read(wordHuntGatewayProvider)
          .getState(sessionId);
      if (!mounted) return;
      _reseedClock(session);
      state = state.copyWith(
        session: session,
        isLoading: false,
        errorMessage: null,
      );
    } on WordHuntApiError catch (error) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not reach the game. Check your connection.',
      );
    }
  }

  /// Starts the clock and fetches the puzzle in one call.
  Future<void> start() async {
    if (state.isSubmitting) return;
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      final session = await _ref.read(wordHuntGatewayProvider).start(sessionId);
      if (!mounted) return;
      _reseedClock(session);
      state = state.copyWith(
        session: session,
        isLoading: false,
        isSubmitting: false,
      );
    } on WordHuntApiError catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, errorMessage: error.message);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Could not start the hunt. Try again.',
      );
    }
  }

  Future<void> submit(List<WordHuntCell> cells) async {
    if (state.isSubmitting) return;
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      final result = await _ref
          .read(wordHuntGatewayProvider)
          .submit(sessionId: sessionId, cells: cells);
      if (!mounted) return;
      _reseedClock(result.session);
      state = state.copyWith(
        session: result.session,
        isSubmitting: false,
        // A miss says nothing and costs nothing: no message, no error,
        // just the pill animating off.
        missCells: result.hit ? null : cells,
        missNonce: result.hit ? state.missNonce : state.missNonce + 1,
      );
    } on WordHuntApiError catch (error) {
      if (!mounted) return;
      // The limiter is not the player's problem to read about mid-hunt:
      // it fires on a double-submit from one drag, and a red banner for
      // that would be noise. The pill simply comes off.
      final quiet = error.code == 'RATE_LIMITED';
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: quiet ? null : error.message,
        missCells: cells,
        missNonce: state.missNonce + 1,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'That guess did not reach the server.',
      );
    }
  }

  Future<void> giveUp() async {
    if (state.isSubmitting) return;
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      final session = await _ref
          .read(wordHuntGatewayProvider)
          .giveUp(sessionId);
      if (!mounted) return;
      _reseedClock(session);
      state = state.copyWith(session: session, isSubmitting: false);
    } on WordHuntApiError catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, errorMessage: error.message);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Could not reach the game. Try again.',
      );
    }
  }

  Future<void> accept() async {
    try {
      await _ref.read(wordHuntGatewayProvider).acceptSession(sessionId);
      await refresh();
    } on WordHuntApiError catch (error) {
      if (!mounted) return;
      state = state.copyWith(errorMessage: error.message);
    }
  }

  Future<void> decline() async {
    try {
      await _ref.read(wordHuntGatewayProvider).declineSession(sessionId);
      await refresh();
    } on WordHuntApiError catch (error) {
      if (!mounted) return;
      state = state.copyWith(errorMessage: error.message);
    }
  }

  @override
  void dispose() {
    _stopwatch.stop();
    super.dispose();
  }
}

final wordHuntProvider =
    StateNotifierProvider.family<WordHuntNotifier, WordHuntUiState, String>(
      (ref, sessionId) => WordHuntNotifier(ref, sessionId),
    );

/// The couple's open invitation or game, for the lobby.
final activeWordHuntSessionProvider =
    FutureProvider.family<WordHuntSession?, String>(
      (ref, relationshipId) =>
          ref.read(wordHuntGatewayProvider).getActiveSession(relationshipId),
    );

/// Creates a session, or returns the one already open.
final wordHuntCreateSessionProvider = FutureProvider.family<String, String>((
  ref,
  relationshipId,
) {
  // A fresh key per provider instance, so a rebuild does not create a
  // second game while a retry of the same call does not either.
  final key = 'word_hunt:$relationshipId:${const Uuid().v4()}';
  return ref
      .read(wordHuntGatewayProvider)
      .createSession(relationshipId: relationshipId, idempotencyKey: key);
});
