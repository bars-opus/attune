import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The game staged for sending, shown where the text field was.
///
/// Picking a game from the sheet used to create the session immediately,
/// which meant the catalogue posted a card the moment you looked at a
/// game -- and backing out left an invitation your partner could see and
/// answer. Selection now stages; only Send reaches the server.
///
/// Deliberately the SAME card the conversation shows, on the sender
/// bubble's colour: what you are about to send should look like what
/// will be sent, so nothing about the result is a surprise.
class GameComposerBar extends ConsumerWidget {
  const GameComposerBar({
    super.key,
    required this.relationshipId,
    required this.gameType,
    required this.onCancel,
  });

  /// Whose conversation. The composer is per-relationship, so a game
  /// staged for one partner never appears in another chat.
  final String relationshipId;

  final String gameType;

  /// Unstages the game. Sending is the composer's job below, because a
  /// send carries the game AND any caption typed with it.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameComposerProvider(relationshipId));
    final chatColors = Theme.of(context).chatColors;
    final colorScheme = Theme.of(context).colorScheme;
    final title = gameTypeDisplayName(gameType);

    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.sm.w, Spacing.xs.h, Spacing.sm.w, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.errorMessage != null)
            Padding(
              padding: EdgeInsets.only(
                bottom: Spacing.xs.h,
                left: Spacing.sm.w,
                right: Spacing.sm.w,
              ),
              child: Text(
                state.errorMessage!,
                style: TextStyle(color: colorScheme.error, fontSize: 12),
              ),
            ),
          // The staged game sits ABOVE the composer, not inside it.
          //
          // Sending a game and writing a note about it are two different
          // things, and the composer is already the place for the second.
          // Putting the game in its own pill above leaves the text field
          // free to be a text field -- so a caption comes for free, on
          // the send path every other message already uses.
          Container(
            // Generous, and deliberately more than the text field's own
            // padding: a line of text FILLS its pill, but a game card is
            // an object sitting IN one, and a tight margin made it read
            // as a card that had burst its container.
            padding: EdgeInsets.symmetric(
              horizontal: Spacing.md.w,
              vertical: Spacing.md.h,
            ),
            // The pill the text field uses -- same surface, same shadow
            // -- so the two read as one composer stacked in two rows.
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(BorderRadiusTokens.xl.r),
              boxShadow: kComposerShadows,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: Spacing.sm.w,
                      vertical: Spacing.xs.h,
                    ),
                    decoration: BoxDecoration(
                      color: chatColors.senderBubble,
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.lg.r,
                      ),
                    ),
                    child: InfoRowWidget(
                      pinAvatar: true,
                      title: title,
                      subtitle: 'Invite them to play',
                      icon: gameGlyphFor(gameType),
                      iconColor: Colors.white,
                      backgroundColor: GamePalette.of(gameType).end,
                      avatarRadius: 40.h,
                      iconSize: 20.h,
                      circularRadius: 12.r,
                      showAvatar: true,
                      showDivider: false,
                      showTrailingArrow: false,
                      titleFontSize: 14,
                      subTitleFontSize: 12,
                      // The sender bubble is the SAME mint green in both
                      // themes, so its ink is the same near-black in
                      // both. A theme-derived onSurface would go white in
                      // dark mode and vanish.
                      titleFontColor: chatColors.onSenderBubble,
                      subTitleFontColor: chatColors.onSenderBubble.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: Spacing.sm.w),
                // Removing the staged game is the only control here now.
                // Send lives on the composer below, because what is being
                // sent is the game AND whatever was typed about it.
                _RemoveButton(
                  onCancel: state.sending ? null : onCancel,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Takes the staged game back off the composer.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onCancel, required this.colorScheme});

  final VoidCallback? onCancel;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onCancel != null,
      label: 'Remove game invitation',
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: colorScheme.onSurface.withValues(alpha: 0.08),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onCancel,
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
