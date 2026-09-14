// lib/features/chat/presentation/screens/message_info_screen.dart
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';

/// Read-only detail view for a single message: a live preview of the
/// bubble, then every timestamp the app actually has for it — sent,
/// delivered, read, edited, viewed-once — each only when it applies to
/// this message's type and status, never a placeholder row for something
/// that never happened.
///
/// Opened from the focused-menu "Info" action. Deliberately takes the
/// [Message] itself rather than an id + a provider lookup: this is a
/// point-in-time snapshot of what the menu was already showing, the same
/// way [MessageActionsSheet]'s own timestamp header works, so info stays
/// consistent with whatever the user just long-pressed even if the
/// message updates (a read receipt landing) the instant after they tap.
class MessageInfoScreen extends StatelessWidget {
  const MessageInfoScreen({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final rows = _buildRows(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Message info', style: textTheme.titleMedium),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The real bubble, not a mock-up of one — MessageBubble with
            // no currentUserId disables its own long-press (canOpenActions
            // reads currentUserId != null), so this can never recursively
            // open the menu that led here.
            Align(
              alignment:
                  message.isMine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                child: MessageBubble(message: message),
              ),
            ),
            Gap(Spacing.lg),
            if (rows.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.md),
                child: Text(
                  'No delivery details yet.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.lg),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      rows[i],
                      if (i != rows.length - 1) const AppDivider(),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One row per timestamp that actually exists and is meaningful for
  /// this message — never a row reading "—" for something that never
  /// happened. Ordered as the events happened: sent first, deleted last
  /// (nothing meaningful can follow a deletion).
  List<Widget> _buildRows(BuildContext context) {
    final rows = <Widget>[];

    // Deleted messages carry no further useful timeline — the tombstone
    // already says who deleted it and there is nothing else to show.
    if (message.isDeleted) {
      rows.add(
        _InfoRow(
          icon: Icons.block_outlined,
          title: message.isMine ? 'You deleted this message' : 'Deleted',
          subtitle:
              message.deletedAt != null
                  ? _formatFull(message.deletedAt!)
                  : null,
        ),
      );
      return rows;
    }

    rows.add(
      _InfoRow(
        icon: Icons.schedule_rounded,
        title: 'Sent',
        subtitle: _formatFull(message.createdAt),
      ),
    );

    if (message.editedAt != null) {
      rows.add(
        _InfoRow(
          icon: Icons.edit_outlined,
          title: 'Edited',
          subtitle: _formatFull(message.editedAt!),
        ),
      );
    }

    // Delivered/read only mean something for a message the viewer SENT —
    // there is no "delivered to you" concept for your own inbox, and this
    // app never tracked it for the other direction.
    if (message.isMine) {
      if (message.deliveredAt != null) {
        rows.add(
          _InfoRow(
            icon: Icons.done_all_rounded,
            title: 'Delivered',
            subtitle: _formatFull(message.deliveredAt!),
          ),
        );
      }
      if (message.readAt != null) {
        rows.add(
          _InfoRow(
            icon: Icons.done_all_rounded,
            iconColor: Theme.of(context).colorScheme.primary,
            title: 'Read',
            subtitle: _formatFull(message.readAt!),
          ),
        );
      } else if (message.status == MessageStatus.failed) {
        rows.add(
          _InfoRow(
            icon: Icons.error_outline_rounded,
            iconColor: Theme.of(context).colorScheme.error,
            title: 'Failed to send',
          ),
        );
      }
    }

    // View-once media (streaks, ephemeral video): when the RECIPIENT
    // opened it, distinct from an ordinary "read" receipt — message.dart
    // tracks the two separately (viewedAt vs readAt) because a view-once
    // open also starts the countdown to the media being destroyed.
    if (message.viewedAt != null) {
      rows.add(
        _InfoRow(
          icon: Icons.visibility_outlined,
          title: message.isMine ? 'Viewed' : 'You viewed this',
          subtitle: _formatFull(message.viewedAt!),
        ),
      );
    }

    return rows;
  }

  String _formatFull(DateTime dateTime) =>
      '${MyDateFormat.toWeekdayMonth(dateTime)} ${dateTime.day}, '
      '${dateTime.year} at ${MyDateFormat.toTime(dateTime)}';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InfoRowWidget(
      title: title,
      subtitle: subtitle ?? '',
      subTitleMaxLines: 1,
      showAvatar: false,
      showDivider: false,
      leadingWidget: Icon(
        icon,
        size: 20,
        color: iconColor ?? colorScheme.onSurfaceVariant,
      ),
      titleStyle: textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      subtitleStyle: textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
    );
  }
}
