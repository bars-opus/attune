import 'package:attune/core/ui/motion/icon_crossfade.dart';
import 'package:attune/core/widgets/focused_action_menu.dart';
import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onRemove,
    this.showStatus = true,
    this.onReply,
    this.onJumpToParent,
    this.isHighlighted = false,
    this.parentDeleted = false,
    this.currentUserId,
    this.isStarred = false,
    this.isPinned = false,
    this.onCopy,
    this.onStar,
    this.onUnstar,
    this.onPin,
    this.onUnpin,
    this.onEdit,
    this.onDelete,
    this.onShowEditHistory,
    this.onReact,
    this.onRemoveReaction,
  });

  final Message message;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;
  final bool showStatus;

  /// Swipe-to-reply target. Null (the default) disables the swipe gesture
  /// entirely — e.g. a read-only/archived conversation has nothing
  /// sensible to reply into.
  final VoidCallback? onReply;

  /// Tapping this message's quoted-parent preview (only rendered when
  /// message.quotedText is non-null) calls this to scroll to and flash the
  /// parent. Null means no tap affordance on the quote block.
  final VoidCallback? onJumpToParent;

  /// True while this is the current jump-to target — see UniversalBubble.
  final bool isHighlighted;

  /// True when this message's replied-to parent has been deleted (Task 8
  /// looks this up from ChatScreen's loaded message list by
  /// message.replyToMessageId). Only meaningful when message.quotedText
  /// is non-null. Defaults to false — an off-screen/unloaded parent is
  /// assumed not deleted rather than guessed at.
  final bool parentDeleted;

  /// Needed to compute Message.canEditOrDelete inside the long-press
  /// sheet. Null disables the long-press menu entirely (e.g. a read-only
  /// archived conversation has nothing sensible to act on) — matches the
  /// existing null-disables-gesture convention onReply already uses.
  final String? currentUserId;
  final bool isStarred;
  final bool isPinned;
  final VoidCallback? onCopy;
  final VoidCallback? onStar;
  final VoidCallback? onUnstar;
  final VoidCallback? onPin;
  final VoidCallback? onUnpin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Tapping the "edited" label calls this with the message, to open a
  /// history view. Null disables the tap affordance (label still renders,
  /// just not interactive) — matches this file's existing null-disables
  /// convention.
  final void Function(Message)? onShowEditHistory;

  /// Called with the selected emoji when the user picks a quick reaction or
  /// an emoji from the full picker. Null disables the reaction affordance
  /// entirely — matches this file's existing null-disables-gesture
  /// convention (`onReply`/`onLongPress`).
  final void Function(String emoji)? onReact;

  /// Reserved for a future "tap your own pill to remove" affordance. Not
  /// yet wired to any gesture in this task — see _buildReactionPills.
  final VoidCallback? onRemoveReaction;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final colorScheme = Theme.of(context).colorScheme;
    final canOpenActions = currentUserId != null && !message.isDeleted;

    final reactionPills = _buildReactionPills(context, message);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        UniversalBubble(
          isMine: isMine,
          bubbleColor:
              isMine ? colorScheme.primary : colorScheme.surfaceContainerHighest,
          onBubbleColor: isMine ? colorScheme.onPrimary : colorScheme.onSurface,
          quotedText: parentDeleted ? 'Original message deleted' : message.quotedText,
          onJumpToParent: message.quotedText == null ? null : onJumpToParent,
          isHighlighted: isHighlighted,
          bubbleKey: ValueKey(message.clientMessageId),
          onLongPress: canOpenActions
              ? (bubbleRect, bubbleSnapshot) => showFocusedActionMenu(
                    context: context,
                    anchorRect: bubbleRect,
                    anchorSnapshot: bubbleSnapshot,
                    quickReactions: const [
                      ReactionQuickOption(emoji: '❤️'),
                      ReactionQuickOption(emoji: '👍'),
                      ReactionQuickOption(emoji: '👎'),
                      ReactionQuickOption(emoji: '😂'),
                      ReactionQuickOption(emoji: '‼️'),
                      ReactionQuickOption(emoji: '❓'),
                    ],
                    onReact: (emoji) => onReact?.call(emoji),
                    onOpenFullPicker: () => _openFullEmojiPicker(context, onReact),
                    actions: buildMessageActionItems(
                      context: context,
                      message: message,
                      currentUserId: currentUserId!,
                      isStarred: isStarred,
                      isPinned: isPinned,
                      onReply: onReply ?? () {},
                      onCopy: onCopy ?? () {},
                      onStar: onStar ?? () {},
                      onUnstar: onUnstar ?? () {},
                      onPin: onPin ?? () {},
                      onUnpin: onUnpin ?? () {},
                      onEdit: onEdit ?? () {},
                      onDelete: onDelete ?? () {},
                    ),
                  )
              : null,
          onReply: onReply,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isImported)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    'Imported from WhatsApp',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              _BubbleBody(message: message, isMine: isMine),
            ],
          ),
          footer: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              if (isStarred)
                Semantics(
                  label: 'Starred',
                  excludeSemantics: true,
                  child: Icon(
                    Icons.star,
                    size: 12,
                    color: isMine ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                  ),
                ),
              Semantics(
                label: _absoluteTimeLabel(context, message.createdAt),
                excludeSemantics: true,
                child: Text(
                  _timeLabel(context, message.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (message.editedAt != null && !message.isDeleted)
                GestureDetector(
                  onTap: onShowEditHistory == null
                      ? null
                      : () => onShowEditHistory!(message),
                  child: Text(
                    'edited',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              if (showStatus && isMine)
                _StatusChip(message: message, onRetry: onRetry),
              if (message.isFailed && onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              if (message.isFailed && onRemove != null)
                TextButton(onPressed: onRemove, child: const Text('Remove')),
            ],
          ),
        ),
        if (reactionPills != null)
          Positioned(
            bottom: -10,
            left: isMine ? null : 12,
            right: isMine ? 12 : null,
            child: reactionPills,
          ),
      ],
    );
  }

  /// Short, locale-aware clock label shown visually (e.g. "3:04 PM").
  static String _timeLabel(BuildContext context, DateTime time) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.jm(locale).format(time);
  }

  /// Full absolute date+time announced to screen readers so relative/short
  /// visual times remain accessible (Spec 11.4). Visual semantics are excluded
  /// so the reader announces this label instead of the terse clock string.
  static String _absoluteTimeLabel(BuildContext context, DateTime time) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMMEEEEd(locale).add_jm().format(time);
  }
}

/// One small pill per distinct emoji on [message], or null if there are
/// none. Same emoji from multiple reactors collapses into ONE pill with a
/// small count badge (never multiple pills for the same emoji). Display
/// only — tapping a pill to toggle your own reaction is explicitly out of
/// scope for this plan (see Task 6's manual smoke-test note).
Widget? _buildReactionPills(BuildContext context, Message message) {
  if (message.reactions.isEmpty) return null;
  final colorScheme = Theme.of(context).colorScheme;

  return Wrap(
    spacing: 4,
    children: [
      for (final entry in message.reactions.entries)
        if (entry.value.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 13)),
                if (entry.value.length > 1) ...[
                  const SizedBox(width: 2),
                  Text(
                    '${entry.value.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
    ],
  );
}

/// Opens the full `emoji_picker_flutter` sheet so the user can react with
/// any emoji, not just the 6 quick-reaction options. Free function (not a
/// method on MessageBubble) since it needs no widget state — mirrors
/// `_showEditDialog`'s free-function shape in chat_screen.dart.
void _openFullEmojiPicker(BuildContext context, void Function(String emoji)? onReact) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SizedBox(
      height: 320,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) {
          onReact?.call(emoji.emoji);
          Navigator.of(sheetContext).pop();
        },
      ),
    ),
  );
}

class _BubbleBody extends StatelessWidget {
  const _BubbleBody({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final color =
        isMine
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface;

    if (message.isDeleted) {
      return Text(
        'This message was deleted',
        style: TextStyle(color: color, fontStyle: FontStyle.italic),
      );
    }

    final children = <Widget>[];
    if (message.hasImage) {
      final provider =
          message.localMediaPath != null
              ? FileImage(File(message.localMediaPath!)) as ImageProvider
              : NetworkImage(message.signedMediaUrl!);
      children.add(
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image(
            image: provider,
            width: 220,
            height: 220,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    if (message.content.trim().isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(Text(message.content, style: TextStyle(color: color)));
    }

    if (children.isEmpty) {
      children.add(Text('Unsupported message', style: TextStyle(color: color)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.message, this.onRetry});

  final Message message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final label = switch (message.status) {
      MessageStatus.queued => 'Queued',
      MessageStatus.sending => 'Sending',
      MessageStatus.sent => 'Sent',
      MessageStatus.delivered => 'Delivered',
      MessageStatus.read => 'Read',
      MessageStatus.failed => 'Failed',
    };

    final icon = switch (message.status) {
      MessageStatus.queued => Icons.schedule_rounded,
      MessageStatus.sending => Icons.sync_rounded,
      MessageStatus.sent => Icons.check_rounded,
      MessageStatus.delivered => Icons.done_all_rounded,
      MessageStatus.read => Icons.done_all_rounded,
      MessageStatus.failed => Icons.error_outline_rounded,
    };

    final color = switch (message.status) {
      MessageStatus.failed => Theme.of(context).colorScheme.error,
      MessageStatus.read => Theme.of(context).colorScheme.primary,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };

    final child = Semantics(
      label: 'Message status: $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconCrossfade(
            child: Icon(icon, key: ValueKey(message.status), size: 14, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (message.status != MessageStatus.failed || onRetry == null) {
      return child;
    }

    return InkWell(onTap: onRetry, child: child);
  }
}
