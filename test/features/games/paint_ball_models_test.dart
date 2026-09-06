import 'package:attune/features/games/paint_ball/analytics/paint_ball_analytics.dart';
import 'package:attune/features/games/paint_ball/models/paint_ball_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sessionJson({int currentRound = 2}) => {
  'session_id': 'session-opaque',
  'relationship_id': 'relationship-opaque',
  'initiator_id': 'user-a',
  'user_a_id': 'user-a',
  'user_b_id': 'user-b',
  'status': 'active',
  'game_type': 'paint_ball',
  'tone': 'playful',
  'current_round': currentRound,
  'total_rounds_completed': 1,
  'current_turn_user_id': 'user-b',
  'lives_a': 3,
  'lives_b': 2,
  'rounds': [
    {
      'round_number': 1,
      'shot_result': 'opening',
      'life_lost': false,
      'shot_position': 2,
      'active_partner_id': 'user-a',
      'created_at': '2026-09-06T12:00:00Z',
    },
  ],
};

void main() {
  test('opening is distinct from both hit and miss', () {
    final result = PaintBallShotResult.fromJson({
      'session_id': 'session-opaque',
      'round_number': 1,
      'shot_result': 'opening',
      'life_lost': false,
      'lives_a': 3,
      'lives_b': 3,
      'knockout': false,
      'existing': false,
    });

    expect(result.isOpening, isTrue);
    expect(result.isHit, isFalse);
    expect(result.isMiss, isFalse);
  });

  test('session parsing restores paint but contains no hiding position', () {
    final session = PaintBallSessionState.fromJson(_sessionJson());

    expect(session.currentRound, 2);
    expect(session.rounds.single.shotPosition, 2);
    expect(session.rounds.single.activePartnerId, 'user-a');
    expect(session.rounds.single.outcome, PaintBallShotOutcome.opening);
    expect(session.rounds.single.toJson(), isNot(contains('hide_position')));
  });

  test('legacy round zero is normalized to the opening round', () {
    final session = PaintBallSessionState.fromJson(
      _sessionJson(currentRound: 0),
    );
    expect(session.currentRound, 1);
  });

  test('choices from an earlier turn can never enable Fire', () {
    final session = PaintBallSessionState.fromJson(_sessionJson());

    final stale = PaintBallUiState(
      phase: PaintBallGamePhase.playing,
      session: session,
      hidePosition: 0,
      shotPosition: 1,
      selectionRound: 1,
    );
    final current = stale.copyWith(selectionRound: 2);

    expect(stale.canFire, isFalse);
    expect(current.canFire, isTrue);
  });

  test('analytics exposes only bounded, content-free properties', () {
    final events = <String, Map<String, Object?>>{};
    final analytics = PaintBallAnalytics(
      capture: (name, properties) => events[name] = properties,
    );

    analytics.sessionStarted(
      sessionId: 'session-opaque',
      tone: 'connecting',
      partnerAuthoredEnabled: true,
    );
    analytics.shotFired(sessionId: 'session-opaque', roundNumber: 3);
    analytics.shotResolved(
      sessionId: 'session-opaque',
      roundNumber: 3,
      hit: true,
    );
    analytics.playerEliminated(
      sessionId: 'session-opaque',
      penaltySource: 'partner_authored',
    );
    analytics.penaltyResolved(sessionId: 'session-opaque', completed: false);
    analytics.sessionCompleted(sessionId: 'session-opaque', roundsCompleted: 7);

    expect(events.keys, contains(PaintBallAnalytics.shotHitEvent));
    expect(events.keys, contains(PaintBallAnalytics.penaltyDeclinedEvent));
    for (final properties in events.values) {
      expect(properties, isNot(contains('prompt')));
      expect(properties, isNot(contains('content')));
      expect(properties, isNot(contains('user_id')));
    }
  });

  test('history page parses cursor and session-only recap fields', () {
    final page = PaintBallHistoryPage.fromJson({
      'items': [
        {
          'session_id': 'session-history',
          'tone': 'romantic',
          'winner_user_id': 'user-b',
          'penalty_type': 'dare',
          'penalty_status': 'declined',
          'total_rounds_completed': 8,
          'completed_at': '2026-09-06T12:00:00Z',
        },
      ],
      'next_cursor': '2026-09-06T12:00:00+00:00',
    });

    expect(page.items, hasLength(1));
    expect(page.items.single.sessionId, 'session-history');
    expect(page.items.single.penaltyStatus, 'declined');
    expect(page.items.single.totalRoundsCompleted, 8);
    expect(page.nextCursor, isNotNull);
  });
}
