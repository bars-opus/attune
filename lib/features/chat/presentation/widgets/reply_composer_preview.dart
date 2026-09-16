import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:flutter/material.dart';

enum ReplyPreviewKind { text, game, image, video, audio, streak, streakOpened }

/// The settled destination for a message-to-composer reply flight.
///
/// Motion is deliberately owned by `ChatScreen`: it knows both measured
/// endpoints and whether the keyboard is already visible. Keeping this widget
/// static prevents a second entrance/reverse animation from fighting the
/// payload flight.
class ReplyComposerPreview extends StatelessWidget {
  const ReplyComposerPreview({
    super.key,
    this.surfaceKey,
    required this.quotedText,
    required this.onClose,
    this.isMine = false,
    this.replyingToLabel = 'you',
    this.kind = ReplyPreviewKind.text,
    this.gameType,
  });

  /// Measures the painted card rather than this widget's outer padding.
  final Key? surfaceKey;
  final String quotedText;
  final VoidCallback onClose;
  final bool isMine;
  final String replyingToLabel;
  final ReplyPreviewKind kind;
  final String? gameType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatColors = theme.chatColors;
    final surfaceColor =
        isMine ? chatColors.senderBubble : theme.colorScheme.surface;
    final foregroundColor =
        isMine ? chatColors.onSenderBubble : theme.colorScheme.onSurface;
    final accentColor =
        isMine ? chatColors.senderMetadata : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: CardInkWell(
        key: surfaceKey,
        color: surfaceColor,
        borderColor:
            isMine ? chatColors.senderMetadata.withValues(alpha: 0.18) : null,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        margin: EdgeInsets.zero,
        enableFeedback: false,
        child: Row(
          children: [
            Container(
              width: 3,
              height: 38,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            if (kind != ReplyPreviewKind.text) ...[
              _ReplyPreviewTypeIcon(kind: kind, gameType: gameType),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Replying to $replyingToLabel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: '\n$quotedText',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foregroundColor.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
              ),
            ),
            IconButton(
              tooltip: 'Cancel reply',
              icon: const Icon(Icons.close, size: 16),
              color: foregroundColor.withValues(alpha: 0.66),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyPreviewTypeIcon extends StatelessWidget {
  const _ReplyPreviewTypeIcon({required this.kind, this.gameType});

  final ReplyPreviewKind kind;
  final String? gameType;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chatColors = Theme.of(context).chatColors;
    // Requested for this media chip: inverse of the surrounding background.
    // ignore: deprecated_member_use
    final adaptiveBackground = colors.onBackground;
    // ignore: deprecated_member_use
    final adaptiveForeground = colors.background;
    final resolvedGameType = gameType;
    final icon =
        kind == ReplyPreviewKind.game && resolvedGameType != null
            ? gameGlyphFor(resolvedGameType)
            : _fallbackIconFor(kind);
    final background =
        kind == ReplyPreviewKind.game && resolvedGameType != null
            ? GamePalette.of(resolvedGameType).end
            : adaptiveBackground;
    final foreground =
        kind == ReplyPreviewKind.game && resolvedGameType != null
            ? Colors.white
            : adaptiveForeground;

    if (kind == ReplyPreviewKind.streakOpened) {
      return SizedBox(
        width: 34,
        height: 34,
        child: Icon(
          Icons.check_box_outline_blank_rounded,
          size: 20,
          color: colors.onSurfaceVariant,
        ),
      );
    }

    if (kind == ReplyPreviewKind.audio) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: chatColors.voiceAccent,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.play_arrow_rounded,
          size: 24,
          color: adaptiveForeground,
        ),
      );
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: foreground),
    );
  }

  IconData _fallbackIconFor(ReplyPreviewKind kind) {
    switch (kind) {
      case ReplyPreviewKind.game:
        return Icons.sports_esports_outlined;
      case ReplyPreviewKind.image:
        return Icons.image_outlined;
      case ReplyPreviewKind.video:
        return Icons.videocam_outlined;
      case ReplyPreviewKind.audio:
        return Icons.play_arrow_rounded;
      case ReplyPreviewKind.streak:
        return Icons.play_arrow_rounded;
      case ReplyPreviewKind.streakOpened:
        return Icons.check_box_outline_blank_rounded;
      case ReplyPreviewKind.text:
        return Icons.chat_bubble_outline_rounded;
    }
  }
}
