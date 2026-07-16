// lib/features/games/paint_ball/presentation/state/paint_ball_provider.dart

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:attune/core/ui/feedback/sound_service.dart';
import '../../models/paint_ball_models.dart';
import '../../services/paint_ball_service.dart';

final paintBallServiceProvider = Provider<PaintBallService>((ref) {
  final supabase = Supabase.instance.client;
  return PaintBallService(supabase);
});

final paintBallCurrentUserIdProvider = Provider<String?>((ref) {
  return Supabase.instance.client.auth.currentUser?.id;
});

class PaintBallSessionNotifier extends StateNotifier<PaintBallUiState> {
  final Ref _ref;
  RealtimeChannel? _realtimeChannel;

  PaintBallService get _service => _ref.read(paintBallServiceProvider);
  SoundService get _sound => _ref.read(soundServiceProvider);

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
          completedAt: DateTime.now(),
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
      await _loadSession(sessionId);
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
        state = state.copyWith(isLoading: false);
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

  Future<void> _loadSession(String sessionId) async {
    final session = await _service.getSessionState(sessionId);
    final phase = _determinePhase(session);
    state = state.copyWith(
      session: session,
      phase: phase,
      isLoading: false,
    );
  }

  Future<void> fireShot({required bool hit}) async {
    final session = state.session;
    if (session == null) return;

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
    _sound.play(AppSound.gameTap);

    try {
      final result = await _service.fireShot(
        sessionId: session.sessionId,
        roundNumber: session.currentRound,
        hit: hit,
      );

      final currentUserId = _ref.read(paintBallCurrentUserIdProvider);
      final nextRounds = [
        ...session.rounds,
        PaintBallRound(
          roundNumber: result.roundNumber,
          shotResult: result.shotResult,
          lifeLost: result.lifeLost,
          createdAt: DateTime.now(),
        ),
      ];

      final updatedSession = session.copyWith(
        currentRound: result.knockout
            ? session.currentRound
            : session.currentRound + 1,
        totalRoundsCompleted: session.totalRoundsCompleted + 1,
        livesA: result.livesA,
        livesB: result.livesB,
        currentTurnUserId: result.currentTurnUserId,
        winnerUserId:
            result.knockout ? currentUserId : session.winnerUserId,
        penaltyType: result.penaltyType,
        penaltyPromptSnapshot: result.penaltyPromptSnapshot,
        penaltyStatus: result.knockout ? 'pending' : null,
        rounds: nextRounds,
        isMyTurn: result.currentTurnUserId == currentUserId,
        isWinner: result.knockout && currentUserId == session.currentTurnUserId,
        isLoser: false,
      );

      state = state.copyWith(
        session: updatedSession,
        phase:
            result.knockout ? PaintBallGamePhase.knockout : PaintBallGamePhase.playing,
        isSubmitting: false,
        showHitFeedback: result.isHit,
        showMissFeedback: result.isMiss,
        showKnockout: result.knockout,
      );
      _sound.play(result.knockout ? AppSound.gameComplete : AppSound.gameReveal);

      if (result.isHit || result.isMiss) {
        await Future.delayed(const Duration(milliseconds: 800));
        state = state.copyWith(
          showHitFeedback: false,
          showMissFeedback: false,
        );
      }

      if (result.knockout) {
        await Future.delayed(const Duration(milliseconds: 1000));
        state = state.copyWith(showKnockout: false);
      }
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _getErrorMessage(e),
        phase: PaintBallGamePhase.playing,
      );
    }
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
    if (error is Exception) {
      return error.toString();
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

final paintBallLivesProvider = Provider<({int myLives, int opponentLives})>((ref) {
  final session = ref.watch(paintBallCurrentSessionProvider);
  final userId = ref.watch(paintBallCurrentUserIdProvider);
  if (session == null) return (myLives: 0, opponentLives: 0);
  return (
    myLives: session.livesForUser(userId),
    opponentLives: session.opponentLivesForUser(userId),
  );
});
