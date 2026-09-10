import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
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

  /// What to call the other player. Their name, not "them" -- the card
  /// sits in a conversation between two people who chose each other,
  /// and "Their move" is how you would describe a stranger.
  ///
  /// Falls back to a neutral word rather than rendering empty: a label
  /// with a hole in it is worse than a formal one.
  String partnerName = 'your partner',
}) {
  switch (state.status) {
    case 'invited':
      // The sender is waiting; the recipient is being asked.
      return viewerIsSender ? 'Waiting for $partnerName' : "Let's play!";
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
            return 'Waiting for $partnerName';
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
      return turn == viewerId ? 'Your move' : "$partnerName's move";
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
  /// Given the game type, the session, and whether tapping should ACCEPT
  /// rather than merely open.
  ///
  /// The picker cannot auto-accept -- choosing "Snakes" from the hub must
  /// not accept an invitation the player has not seen -- so the decision
  /// is made here, where the card knows whose invite it is and what state
  /// it is in, and passed on rather than re-derived downstream.
  final void Function(String gameType, String sessionId, bool autoAccept) onTap;

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
              partnerName: partnerNameOr(ref, fallback: 'your partner'),
            );

    // A finished or abandoned game is a record, not a destination: tapping
    // it would resume or restart something the players are done with.
    final isOpenable =
        state != null &&
        state.status != 'completed' &&
        state.status != 'abandoned';

    // Tapping an invitation SOMEBODY ELSE sent accepts it and drops you
    // into the game -- one tap from "they invited me" to playing.
    //
    // Never for your own invitation: that tap goes to the lobby, where
    // the useful action is cancelling. And never for an active game,
    // which is already accepted.
    final autoAccept = state?.status == 'invited' && !viewerIsSender;

    return Semantics(
      button: isOpenable,
      label: '$title. $label',
      child: InkWell(
        onTap: isOpenable ? () => onTap(gameType, sessionId, autoAccept) : null,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
        child: Container(
          width: 240.w,
          padding: EdgeInsets.symmetric(
            horizontal: Spacing.sm.w,
            vertical: Spacing.xs.h,
          ),
          decoration: BoxDecoration(
            // Opaque now that the bubble no longer paints behind it. At
            // 55% the card was translucent over whatever surface it sat
            // on, which is why it took the sender bubble's accent colour
            // and read as tinted.
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.10),
            ),
          ),
          // The same row the games hub uses, rather than a bespoke column.
          //
          // The card was a 220pt column with an 84pt icon centred above
          // the title, which made a one-line status message occupy the
          // height of a photo in the transcript. A game card is a small
          // piece of state -- whose move it is -- and a row says that in
          // the space it deserves.
          //
          // The glyph and colour go straight to the row rather than
          // through GameIcon: InfoRowWidget sizes a leadingWidget to
          // avatarRadius and centres it, so passing a pre-sized tile
          // fights it for control. Its own IconAvatar does the sizing.
          child: InfoRowWidget(
            pinAvatar: true,
            title: title,
            subtitle: label,
            icon: gameGlyphFor(gameType),
            iconColor: Colors.white,
            backgroundColor: GamePalette.of(gameType).end,
            avatarRadius: 44.h,
            iconSize: 22.h,
            circularRadius: 12.r,
            // TRUE, or IconAvatar drops its coloured container and the
            // game's identity with it.
            showAvatar: true,
            showDivider: false,
            showTrailingArrow: isOpenable,
            titleFontSize: 14,
            subTitleFontSize: 12,
            onTap:
                isOpenable
                    ? () => onTap(gameType, sessionId, autoAccept)
                    : null,
          ),
        ),
      ),
    );
  }
}
