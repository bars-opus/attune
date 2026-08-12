import 'package:attune/core/ui/motion/icon_crossfade.dart';
import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
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

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final colorScheme = Theme.of(context).colorScheme;

    return UniversalBubble(
      isMine: isMine,
      bubbleColor:
          isMine ? colorScheme.primary : colorScheme.surfaceContainerHighest,
      onBubbleColor: isMine ? colorScheme.onPrimary : colorScheme.onSurface,
      quotedText: message.quotedText,
      onJumpToParent: message.quotedText == null ? null : onJumpToParent,
      isHighlighted: isHighlighted,
      slidableKey: ValueKey(message.clientMessageId),
      startActionPane:
          onReply == null
              ? null
              : ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.25,
                // Reply never removes the message from the list, so this
                // must NEVER actually dismiss — same pattern
                // ForumPostBubble/CommentThreadScreen use: fire onReply
                // from confirmDismiss and veto (return false) to get the
                // past-threshold full-swipe gesture without entering
                // Slidable's resize/removal flow.
                dismissible: DismissiblePane(
                  confirmDismiss: () async {
                    onReply!();
                    return false;
                  },
                  onDismissed: () {},
                  closeOnCancel: true,
                ),
                children: [
                  SlidableAction(
                    onPressed: (_) => onReply!(),
                    backgroundColor:
                        isMine
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                    foregroundColor:
                        isMine ? colorScheme.onPrimary : colorScheme.onSurface,
                    icon: Icons.reply,
                    label: 'Reply',
                  ),
                ],
              ),
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
          Semantics(
            label: _absoluteTimeLabel(context, message.createdAt),
            excludeSemantics: true,
            child: Text(
              _timeLabel(context, message.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
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
