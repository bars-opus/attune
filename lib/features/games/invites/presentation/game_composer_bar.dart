import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
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
    required this.onSend,
    required this.onCancel,
  });

  /// Whose conversation. The composer is per-relationship, so a game
  /// staged for one partner never appears in another chat.
  final String relationshipId;

  final String gameType;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameComposerProvider(relationshipId));
    final chatColors = Theme.of(context).chatColors;
    final colorScheme = Theme.of(context).colorScheme;
    final title = gameTypeDisplayName(gameType);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.sm.w,
        vertical: Spacing.xs.h,
      ),
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
          Row(
            children: [
              // Cancel first, in the position the attach button occupies
              // in the normal composer: the thing that puts the text
              // field back is where the thing that replaced it was.
              IconButton(
                onPressed: state.sending ? null : onCancel,
                icon: const Icon(Icons.close_rounded),
                iconSize: 22,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                tooltip: 'Cancel',
              ),
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
                    // Says what Send will do, in the words the card will
                    // use once it exists.
                    subtitle: 'Invite them to play',
                    icon: gameGlyphFor(gameType),
                    iconColor: Colors.white,
                    backgroundColor: GamePalette.of(gameType).end,
                    avatarRadius: 44.h,
                    iconSize: 22.h,
                    circularRadius: 12.r,
                    showAvatar: true,
                    showDivider: false,
                    showTrailingArrow: false,
                    titleFontSize: 14,
                    subTitleFontSize: 12,
                  ),
                ),
              ),
              SizedBox(width: Spacing.xs.w),
              _SendButton(sending: state.sending, onSend: onSend),
            ],
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.sending, required this.onSend});

  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      enabled: !sending,
      label: 'Send game invitation',
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: colorScheme.primary,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: sending ? null : onSend,
            child: Center(
              child:
                  sending
                      // The send is in flight. A spinner in the button's
                      // own place, rather than over the card, so the
                      // thing being sent stays readable.
                      ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                      : Icon(
                        Icons.send_rounded,
                        size: 20,
                        color: colorScheme.onPrimary,
                      ),
            ),
          ),
        ),
      ),
    );
  }
}
