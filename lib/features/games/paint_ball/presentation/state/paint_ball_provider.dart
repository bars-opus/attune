// lib/features/games/paint_ball/presentation/state/paint_ball_provider.dart

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import '../../analytics/paint_ball_analytics.dart';
import '../../models/paint_ball_models.dart';
import '../../services/paint_ball_service.dart';
import '../widgets/paint_ball_field.dart' show kPaintBallPositions;

final paintBallServiceProvider = Provider<PaintBallGateway>((ref) {
  final supabase = Supabase.instance.client;
  return PaintBallService(supabase);
});

final paintBallCurrentUserIdProvider = Provider<String?>((ref) {
  return Supabase.instance.client.auth.currentUser?.id;
});

final paintBallAnalyticsProvider = Provider<PaintBallAnalytics>((ref) {
  return const PaintBallAnalytics();
});

/// Where this player hid last round, if the game is already under way.
///
/// Read from the resolved rounds rather than kept in memory: a player who
/// closes the app mid-match and returns must find themselves where they
/// left off, not somewhere new.
int? _lastHideFor(PaintBallSessionState session, String? userId) {
  if (userId == null) return null;
  for (final round in session.rounds.reversed) {
    if (round.activePartnerId == userId && round.hidePosition != null) {
      return round.hidePosition;
    }
  }
  return null;
}

final _random = Random();

class PaintBallSessionNotifier extends StateNotifier<PaintBallUiState> {
  final Ref _ref;
  RealtimeChannel? _realtimeChannel;

  PaintBallGateway get _service => _ref.read(paintBallServiceProvider);
  SoundService get _sound => _ref.read(soundServiceProvider);
  Haptics get _haptics => _ref.read(hapticsProvider);
  PaintBallAnalytics get _analytics => _ref.read(paintBallAnalyticsProvider);

  PaintBallSessionNotifier(this._ref) : super(const PaintBallUiState());

  Future<void> createSession({
    required String relationshipId,
    String tone = 'playful',
    bool allowPartnerAuthored = false,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _service.createSession(
        relationshipId: relationshipId,
        tone: tone,
        allowPartnerAuthored: allowPartnerAuthored,
      );

      await _loadSession(response.sessionId);
      _subscribeToSession(response.sessionId);
      if (!response.existing) {
        _analytics.sessionStarted(
          sessionId: response.sessionId,
          tone: tone,
          partnerAuthoredEnabled: allowPartnerAuthored,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _getErrorMessage(e),
      );
    }
  }

  Future<void> acceptSession(String sessionId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      await _service.acceptSession(sessionId);
      await _loadSession(sessionId);
      _subscribeToSession(sessionId);
      _analytics.sessionAccepted(sessionId: sessionId);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _getErrorMessage(e),
      );
    }
  }

  Future<void> declineSession(String sessionId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      await _service.declineSession(sessionId);
      state = state.copyWith(
        isLoading: false,
        phase: PaintBallGamePhase.ended,
        session: state.session?.copyWith(
          status: 'abandoned',
          abandonedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _getErrorMessage(e),
      );
    }
  }

  Future<void> loadSession(String sessionId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      await _loadSession(sessionId, resetTransient: true);
      _subscribeToSession(sessionId);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _getErrorMessage(e),
      );
    }
  }

  /// Looks for an existing resumable session for the couple (invited or active)
  /// and loads it if present. This is how the INVITED partner discovers an
  /// incoming invite — their lobby opens with only a relationship id and no
  /// session, so without this the Accept/Decline UI could never appear.
  Future<void> loadActiveSession(String relationshipId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final session = await _service.getActiveSession(relationshipId);
      if (session == null) {
        _realtimeChannel?.unsubscribe();
        _realtimeChannel = null;
        state = const PaintBallUiState();
        return;
      }
      state = state.copyWith(
        session: session,
        phase: _determinePhase(session),
        isLoading: false,
      );
      _subscribeToSession(session.sessionId);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _getErrorMessage(e),
      );
    }
  }

  Future<void> _loadSession(
    String sessionId, {
    bool resetTransient = false,
  }) async {
    final session = await _service.getSessionState(sessionId);
    final phase = _determinePhase(session);
    final currentUserId = _ref.read(paintBallCurrentUserIdProvider);
    final previousSession = state.session;
    final shouldRevealPenalty =
        session.hasPendingPenalty &&
        session.isLoser &&
        (previousSession?.sessionId != session.sessionId ||
            previousSession?.hasPendingPenalty != true);
    final becameMyTurn =
        session.currentTurnUserId == currentUserId &&
        previousSession?.currentTurnUserId != currentUserId;
    // A player always stands somewhere. Starting with no position meant
    // the board opened empty -- no character to see, and nothing to move
    // from -- so the first thing a player did was place themselves rather
    // than reposition. Spec 3.1: you are dealt a cover and may change it.
    //
    // On a later round the previous cover carries forward, so "stay where
    // you are" is a real choice made by doing nothing rather than by
    // re-picking the same spot.
    final carriedHide =
        _lastHideFor(session, currentUserId) ??
        _random.nextInt(kPaintBallPositions);

    state = state.copyWith(
      session: session,
      phase: phase,
      isLoading: false,
      hidePosition:
          resetTransient || becameMyTurn
              ? carriedHide
              : (state.hidePosition ?? carriedHide),
      shotPosition: resetTransient || becameMyTurn ? null : state.shotPosition,
      // Stamped alongside the carried cover. canFire tests that both
      // choices belong to THIS round, and a carried position that left
      // this null made "stay where you are" impossible to act on: the
      // player aimed, and firing stayed disabled until they re-tapped a
      // cover they were already standing in.
      selectionRound:
          resetTransient || becameMyTurn
              ? session.currentRound
              : (state.selectionRound ?? session.currentRound),
      revealedPartnerPosition:
          resetTransient || becameMyTurn ? null : state.revealedPartnerPosition,
      lastOutcome: resetTransient || becameMyTurn ? null : state.lastOutcome,
      showHitFeedback:
          resetTransient || becameMyTurn ? false : state.showHitFeedback,
      showMissFeedback:
          resetTransient || becameMyTurn ? false : state.showMissFeedback,
    );
    if (shouldRevealPenalty) {
      _sound.play(AppSound.gamePenaltyReveal);
      _haptics.light();
    }
  }

  /// Chooses where to hide this turn.
  void selectHide(int position) {
    if (state.isSubmitting) return;
    _sound.play(AppSound.gameTap);
    _haptics.selection();
    state = state.copyWith(
      hidePosition: position,
      selectionRound: state.session?.currentRound,
    );
  }

  /// Chooses where to shoot.
  void selectShot(int position) {
    if (state.isSubmitting) return;
    _sound.play(AppSound.gameTap);
    _haptics.selection();
    state = state.copyWith(
      shotPosition: position,
      selectionRound: state.session?.currentRound,
    );
  }

  /// Marks the queued replay as played.
  ///
  /// Called by the field when its animation finishes, or immediately when
  /// the viewer skips it. Without this a reopened game would replay the
  /// same round every time it loaded.
  void clearReplay() {
    if (state.pendingReplay == null) return;
    state = state.copyWith(
      pendingReplay: null,
      // The reveal ends with the replay: the opponent's triangle goes back
      // into hiding, so the next guess starts from nothing again.
      revealedPartnerPosition: null,
      hidePosition: null,
      shotPosition: null,
    );
  }

  /// Commits the turn: hide here, shoot there.
  ///
  /// The server resolves the shot against where the partner actually hid,
  /// so nothing here decides a hit. What comes back includes their
  /// position, which is shown only now -- too late to change this shot,
  /// and the best read available for the next one.
  Future<void> takeTurn() async {
    final session = state.session;
    if (session == null) return;

    final hide = state.hidePosition;
    final shot = state.shotPosition;
    if (hide == null || shot == null) return;

    if (!session.isCurrentUserTurn(_ref.read(paintBallCurrentUserIdProvider))) {
      state = state.copyWith(errorMessage: 'It\'s not your turn.');
      return;
    }

    if (session.isCompleted || session.isAbandoned) {
      state = state.copyWith(errorMessage: 'This game has already ended.');
      return;
    }

    if (state.isSubmitting) return;

    state = state.copyWith(
      isSubmitting: true,
      errorMessage: null,
      phase: PaintBallGamePhase.shotAnimating,
    );
    _sound.play(AppSound.gameFire);
    _haptics.light();
    _analytics.shotFired(
      sessionId: session.sessionId,
      roundNumber: session.currentRound,
    );

    try {
      final result = await _service.takeTurn(
        sessionId: session.sessionId,
        roundNumber: session.currentRound,
        hidePosition: hide,
        shotPosition: shot,
      );

      final currentUserId = _ref.read(paintBallCurrentUserIdProvider);

      // The opener's half. Nothing resolved and nothing was revealed --
      // the partner is simply up now.
      if (!result.isResolved) {
        state = state.copyWith(
          session: session.copyWith(
            currentTurnUserId: result.currentTurnUserId,
            isMyTurn: false,
          ),
          phase: PaintBallGamePhase.playing,
          isSubmitting: false,
          awaitingPartner: true,
        );
        return;
      }

      // The closer's half: the round resolved, so there is a replay.
      final updatedSession = session.copyWith(
        currentRound:
            result.knockout ? session.currentRound : session.currentRound + 1,
        livesA: result.livesA,
        livesB: result.livesB,
        currentTurnUserId: result.currentTurnUserId,
        winnerUserId: result.winnerUserId,
        penaltyStatus: result.knockout ? 'pending' : null,
        isMyTurn: result.currentTurnUserId == currentUserId,
        isWinner: result.winnerUserId == currentUserId,
        isLoser:
            result.winnerUserId != null && result.winnerUserId != currentUserId,
      );

      final mine =
          result.opener!.userId == currentUserId
              ? result.opener!
              : result.closer!;
      final theirs =
          result.opener!.userId == currentUserId
              ? result.closer!
              : result.opener!;

      final replay = PaintBallReplay(
        roundNumber: result.roundNumber,
        mine: mine,
        theirs: theirs,
        knockout: result.knockout,
        doubleKnockout: result.doubleKnockout,
      );

      state = state.copyWith(
        session: updatedSession,
        phase: PaintBallGamePhase.playing,
        isSubmitting: false,
        awaitingPartner: false,
        // The replay is queued rather than played here: the widget owns the
        // animation clock, and driving it from state would make the
        // provider responsible for frames.
        pendingReplay: replay,
        lastReplay: replay,
        penalties: result.penalties,
      );

      _analytics.shotResolved(
        sessionId: session.sessionId,
        roundNumber: result.roundNumber,
        hit: mine.isHit,
      );

      if (result.knockout) {
        _analytics.playerEliminated(
          sessionId: session.sessionId,
          penaltySource: result.penalties.isEmpty ? 'app_random' : 'app_random',
        );
      }
    } on PaintBallApiError catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        phase: PaintBallGamePhase.playing,
        errorMessage: error.message,
      );
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        phase: PaintBallGamePhase.playing,
        errorMessage: 'Could not send that turn. Please try again.',
      );
    }
  }

  /// Clears the previous turn's choices and reveal, ready for a new one.
  void beginNextTurn() {
    state = state.copyWith(
      hidePosition: null,
      shotPosition: null,
      revealedPartnerPosition: null,
      showHitFeedback: false,
      showMissFeedback: false,
      showKnockout: false,
      lastOutcome: null,
      selectionRound: null,
      // The previous round's reveal goes with it. Leaving it up would
      // show a player last round's result while they choose this one.
      lastReplay: null,
      pendingReplay: null,
    );
  }

  Future<void> resolvePenalty({required bool completed}) async {
    final session = state.session;
    if (session == null) return;

    if (!session.hasPendingPenalty) {
      state = state.copyWith(errorMessage: 'No pending penalty to resolve.');
      return;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: null);

    try {
      await _service.resolvePenalty(
        sessionId: session.sessionId,
        outcome: completed ? 'completed' : 'declined',
      );

      state = state.copyWith(
        session: session.copyWith(
          penaltyStatus: completed ? 'completed' : 'declined',
          status: 'completed',
          completedAt: DateTime.now(),
        ),
        isSubmitting: false,
        phase: PaintBallGamePhase.ended,
      );
      _analytics.penaltyResolved(
        sessionId: session.sessionId,
        completed: completed,
      );
      _analytics.sessionCompleted(
        sessionId: session.sessionId,
        roundsCompleted: session.totalRoundsCompleted,
      );
      _sound.play(AppSound.gameComplete);
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _getErrorMessage(e),
      );
    }
  }

  void _subscribeToSession(String sessionId) {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = _service.subscribeToSession(
      sessionId,
      onUpdate: (_) => unawaited(_loadSession(sessionId)),
    );
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  PaintBallGamePhase _determinePhase(PaintBallSessionState session) {
    if (session.isCompleted || session.isAbandoned) {
      return PaintBallGamePhase.ended;
    }
    if (session.hasPendingPenalty) {
      return PaintBallGamePhase.knockout;
    }
    if (session.isInvited) {
      return PaintBallGamePhase.lobby;
    }
    if (session.isActive && session.currentTurnUserId == null) {
      return PaintBallGamePhase.waiting;
    }
    if (session.isActive) {
      return PaintBallGamePhase.playing;
    }
    return PaintBallGamePhase.lobby;
  }

  String _getErrorMessage(dynamic error) {
    if (error is PaintBallApiError) {
      return error.message;
    }
    return 'Something went wrong. Please try again.';
  }

  void reset() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    state = const PaintBallUiState();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }
}

final paintBallSessionProvider =
    StateNotifierProvider<PaintBallSessionNotifier, PaintBallUiState>((ref) {
      return PaintBallSessionNotifier(ref);
    });

final paintBallCurrentSessionProvider = Provider<PaintBallSessionState?>((ref) {
  return ref.watch(paintBallSessionProvider).session;
});

final paintBallGamePhaseProvider = Provider<PaintBallGamePhase>((ref) {
  return ref.watch(paintBallSessionProvider).phase;
});

final paintBallIsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(paintBallSessionProvider).isLoading;
});

final paintBallErrorProvider = Provider<String?>((ref) {
  return ref.watch(paintBallSessionProvider).errorMessage;
});

final paintBallIsMyTurnProvider = Provider<bool>((ref) {
  final session = ref.watch(paintBallCurrentSessionProvider);
  final userId = ref.watch(paintBallCurrentUserIdProvider);
  if (session == null) return false;
  return session.isCurrentUserTurn(userId);
});

final paintBallLivesProvider = Provider<({int myLives, int opponentLives})>((
  ref,
) {
  final session = ref.watch(paintBallCurrentSessionProvider);
  final userId = ref.watch(paintBallCurrentUserIdProvider);
  if (session == null) return (myLives: 0, opponentLives: 0);
  return (
    myLives: session.livesForUser(userId),
    opponentLives: session.opponentLivesForUser(userId),
  );
});
