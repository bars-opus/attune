typedef PaintBallEventCapture =
    void Function(String eventName, Map<String, Object?> properties);

/// Privacy-bounded Paint Ball analytics.
///
/// Only opaque session identifiers and coarse game metadata are accepted here.
/// Prompt text, player identity, answers, and relationship content have no API
/// surface, which keeps them out of analytics by construction.
class PaintBallAnalytics {
  const PaintBallAnalytics({PaintBallEventCapture? capture})
    : _capture = capture;

  final PaintBallEventCapture? _capture;

  static const sessionStartedEvent = 'paint_ball_session_started';
  static const sessionAcceptedEvent = 'paint_ball_session_accepted';
  static const shotFiredEvent = 'paint_ball_shot_fired';
  static const shotHitEvent = 'paint_ball_shot_hit';
  static const shotMissedEvent = 'paint_ball_shot_missed';
  static const playerEliminatedEvent = 'paint_ball_player_eliminated';
  static const penaltyCompletedEvent = 'paint_ball_penalty_completed';
  static const penaltyDeclinedEvent = 'paint_ball_penalty_declined';
  static const sessionCompletedEvent = 'paint_ball_session_completed';

  void sessionStarted({
    required String sessionId,
    required String tone,
    required bool partnerAuthoredEnabled,
  }) => _emit(sessionStartedEvent, {
    'session_id': sessionId,
    'tone': tone,
    'partner_authored_enabled': partnerAuthoredEnabled,
  });

  void sessionAccepted({required String sessionId}) =>
      _emit(sessionAcceptedEvent, {'session_id': sessionId});

  void shotFired({required String sessionId, required int roundNumber}) =>
      _emit(shotFiredEvent, {
        'session_id': sessionId,
        'round_number': roundNumber,
      });

  void shotResolved({
    required String sessionId,
    required int roundNumber,
    required bool hit,
  }) => _emit(hit ? shotHitEvent : shotMissedEvent, {
    'session_id': sessionId,
    'round_number': roundNumber,
  });

  void playerEliminated({
    required String sessionId,
    required String penaltySource,
  }) => _emit(playerEliminatedEvent, {
    'session_id': sessionId,
    'penalty_source': penaltySource,
  });

  void penaltyResolved({required String sessionId, required bool completed}) =>
      _emit(completed ? penaltyCompletedEvent : penaltyDeclinedEvent, {
        'session_id': sessionId,
      });

  void sessionCompleted({
    required String sessionId,
    required int roundsCompleted,
  }) => _emit(sessionCompletedEvent, {
    'session_id': sessionId,
    'rounds_completed': roundsCompleted,
  });

  void _emit(String eventName, Map<String, Object?> properties) {
    try {
      _capture?.call(eventName, properties);
    } catch (_) {
      // Product analytics must never interrupt a game action.
    }
  }
}
