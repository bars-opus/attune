import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a live session stands for this viewer.
///
/// One mapping from the card state the chat already computes, so the hub,
/// every landing page and the chat card can never disagree about whose
/// move it is.
GameLandingState landingStateFromCard({
  required GameCardState card,
  required String sessionId,
  required String viewerId,
  // The viewer is game_sessions.initiator_id.
  required bool viewerStarted,
  String? partnerName,
}) {
  final round = card.currentRound ?? 0;
  final total = card.totalRounds ?? 0;
  return GameLandingState(
    status: _status(card, viewerId: viewerId, viewerStarted: viewerStarted),
    sessionId: sessionId,
    partnerName: partnerName,
    caption: round > 0 && total > 0 ? 'Round $round of $total' : null,
  );
}

GameLandingStatus _status(
  GameCardState card, {
  required String viewerId,
  required bool viewerStarted,
}) {
  switch (card.status) {
    case 'invited':
      return viewerStarted
          ? GameLandingStatus.waiting
          : GameLandingStatus.invited;
    case 'active':
      final turn = card.currentTurnUserId;
      if (turn != null) {
        return turn == viewerId
            ? GameLandingStatus.yourTurn
            : GameLandingStatus.waiting;
      }
      // No turn order: both answer the same round. Waiting only when the
      // answers say so for certain. The round-state read can fail, and a
      // wrong "waiting" would lock the game shut.
      if (card.viewerAnswered == true && card.partnerAnswered == false) {
        return GameLandingStatus.waiting;
      }
      return GameLandingStatus.yourTurn;
    case 'completed':
      return GameLandingStatus.finished;
    default:
      return GameLandingStatus.fresh;
  }
}

/// Watches one session live. Loading, or signed out, is
/// GameLandingStatus.loading with the sessionId set.
GameLandingState watchSessionLanding(
  WidgetRef ref, {
  required String sessionId,
  required String? initiatorId,
}) {
  final viewerId = ref.watch(currentUserIdProvider);
  final card = ref.watch(gameCardProvider(sessionId)).valueOrNull;
  // The name is not waited for: the button falls back to "your partner".
  final partnerName = ref.watch(gamePartnerNameProvider).valueOrNull;
  if (viewerId == null || card == null) {
    return GameLandingState(
      status: GameLandingStatus.loading,
      sessionId: sessionId,
    );
  }
  return landingStateFromCard(
    card: card,
    sessionId: sessionId,
    viewerId: viewerId,
    viewerStarted: initiatorId != null && initiatorId == viewerId,
    partnerName: partnerName,
  );
}
