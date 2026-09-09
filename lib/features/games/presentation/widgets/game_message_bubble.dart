import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';

/// The status line a game card shows, from the viewer's perspective.
///
/// Kept as a pure function of (state, viewer) so it can be tested without
/// a widget: the same session reads "Your move" to one partner and "Their
/// move" to the other, and getting that backwards is the one bug that
/// would make the whole feature actively misleading.
String gameCardLabel({
  required GameCardState state,
  required String viewerId,
  required bool viewerIsSender,
}) {
  switch (state.status) {
    case 'invited':
      // The sender is waiting; the recipient is being asked.
      return viewerIsSender ? 'Waiting for them' : "Let's play!";
    case 'completed':
      final winner = state.winnerUserId;
      // Not every game names a winner -- 36 Questions and the session
      // games simply finish -- so a null winner is "done", not a loss.
      if (winner == null) return 'Finished';
      return winner == viewerId ? 'You won!' : 'You lost';
    case 'abandoned':
      return 'Ended';
    case 'active':
      final turn = state.currentTurnUserId;
      if (turn == null) {
        // Session games have no turn order -- both partners answer the
        // same round -- so "whose move" comes from who has answered it.
        // This is what lets a player leave the waiting screen: the card
        // carries the state they were staring at a spinner for.
        final viewerAnswered = state.viewerAnswered;
        final partnerAnswered = state.partnerAnswered;
        if (viewerAnswered != null && partnerAnswered != null) {
          if (viewerAnswered && !partnerAnswered) {
            return 'Waiting for your partner';
          }
          if (!viewerAnswered && partnerAnswered) {
            return 'Your turn';
          }
        }

        // current_round defaults to 0 and the session games never update
        // it -- they track progress on the rounds themselves -- so a card
        // showing it read "Round 0 of 8", which is not a round anyone can
        // be on. Displayed as 1-based, and only when it is a real round.
        final round = state.currentRound;
        final total = state.totalRounds;
        if (round != null && total != null && total > 0 && round > 0) {
          return 'Round $round of $total';
        }
        return 'Tap to play';
      }
      return turn == viewerId ? 'Your move' : 'Their move';
    default:
      return 'In progress';
  }
}

/// A game invite rendered inside the conversation.
///
/// One of these exists per game for the game's whole life: it reads live
/// from game_sessions, so the label changes as the game moves rather than
/// the chat filling with a card per turn. That matters more here than in
/// iMessage -- a 36 Questions journey runs for dozens of rounds, and a
/// card each would bury the conversation it sits inside.
class GameMessageBubble extends ConsumerWidget {
  const GameMessageBubble({
    super.key,
    required this.sessionId,
    required this.viewerId,
    required this.viewerIsSender,
    required this.onTap,
    this.fallbackLabel,
  });

  final String sessionId;
  final String viewerId;
  final bool viewerIsSender;

  /// Called with the game_type, so the caller owns routing.
  final void Function(String gameType) onTap;

  /// Shown while the session is still loading -- the game's name, already
  /// on the message row. Without it the card flashes empty on every build.
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final session = ref.watch(gameCardProvider(sessionId));

    final state = session.valueOrNull;
    final gameType = state?.gameType ?? '';
    final title =
        gameType.isEmpty
            ? (fallbackLabel ?? 'Game')
            : gameTypeDisplayName(gameType);

    final label =
        state == null
            ? '…'
            : gameCardLabel(
              state: state,
              viewerId: viewerId,
              viewerIsSender: viewerIsSender,
            );

    // A finished or abandoned game is a record, not a destination: tapping
    // it would resume or restart something the players are done with.
    final isOpenable =
        state != null &&
        state.status != 'completed' &&
        state.status != 'abandoned';

    return Semantics(
      button: isOpenable,
      label: '$title. $label',
      child: InkWell(
        onTap: isOpenable ? () => onTap(gameType) : null,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
        child: Container(
          width: 220.w,
          padding: EdgeInsets.all(Spacing.md.w),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The game's tile, in its own colour.
              //
              // No fallback branch any more: every game has a palette, so
              // the "art exists / art does not" split that used to live
              // here is gone. Two illustrations beside six tinted discs
              // is what made this look unfinished.
              Center(
                child: GameIcon(
                  gameType: gameType,
                  size: 84.h,
                  // Bare here: the chat card has no colour of its own.
                  filled: true,
                ),
              ),
              SizedBox(height: Spacing.sm.h),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
