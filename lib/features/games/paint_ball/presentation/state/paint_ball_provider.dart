// lib/features/games/paint_ball/presentation/state/paint_ball_provider.dart

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import '../../analytics/paint_ball_analytics.dart';
import '../../models/paint_ball_models.dart';
import '../../services/paint_ball_service.dart';

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
    state = state.copyWith(
      session: session,
      phase: phase,
      isLoading: false,
      hidePosition: resetTransient || becameMyTurn ? null : state.hidePosition,
      shotPosition: resetTransient || becameMyTurn ? null : state.shotPosition,
      selectionRound:
          resetTransient || becameMyTurn ? null : state.selectionRound,
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
      final nextRounds = [
        ...session.rounds.where(
          (round) => round.roundNumber != result.roundNumber,
        ),
        PaintBallRound(
          roundNumber: result.roundNumber,
          shotResult: result.shotResult,
          lifeLost: result.lifeLost,
          createdAt: DateTime.now(),
          shotPosition: shot,
          activePartnerId: currentUserId,
        ),
      ]..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));

      final updatedSession = session.copyWith(
        currentRound:
            result.knockout ? session.currentRound : session.currentRound + 1,
        totalRoundsCompleted:
            session.totalRoundsCompleted < nextRounds.length
                ? nextRounds.length
                : session.totalRoundsCompleted,
        livesA: result.livesA,
        livesB: result.livesB,
        currentTurnUserId: result.currentTurnUserId,
        winnerUserId: result.knockout ? currentUserId : session.winnerUserId,
        penaltyType: result.penaltyType,
        penaltySource: result.penaltySource,
        penaltyPromptSnapshot: result.penaltyPromptSnapshot,
        penaltyStatus: result.knockout ? 'pending' : null,
        rounds: nextRounds,
        isMyTurn: result.currentTurnUserId == currentUserId,
        isWinner: result.knockout,
        isLoser: false,
      );

      state = state.copyWith(
        session: updatedSession,
        phase:
            result.knockout
                ? PaintBallGamePhase.knockout
                : PaintBallGamePhase.playing,
        isSubmitting: false,
        showHitFeedback: result.isHit,
        showMissFeedback: result.isMiss,
        showKnockout: result.knockout,
        lastOutcome: result.outcome,
        // Held after the turn so the reveal stays on screen while the
        // player reads it; cleared when they start the next turn.
        revealedPartnerPosition: result.defenderWasAt,
      );

      if (result.knockout) {
        _analytics.playerEliminated(
          sessionId: session.sessionId,
          penaltySource: result.penaltySource ?? 'app_random',
        );
        _sound.play(AppSound.gameKnockout);
        _haptics.medium();
      } else if (result.isHit) {
        _analytics.shotResolved(
          sessionId: session.sessionId,
          roundNumber: result.roundNumber,
          hit: true,
        );
        _sound.play(AppSound.gameHit);
        _haptics.medium();
      } else if (result.isMiss) {
        _analytics.shotResolved(
          sessionId: session.sessionId,
          roundNumber: result.roundNumber,
          hit: false,
        );
        _sound.play(AppSound.gameMiss);
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
