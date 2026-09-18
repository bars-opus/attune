import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Builds the six-action list (Reply/Copy/Star/Pin/Edit/Delete) for a
/// message's long-press menu — Edit/Delete are omitted (not
/// shown-disabled) once [Message.canEditOrDelete] is false, matching the
/// design spec's "no dead menu item that invites a confused tap"
/// decision. Pure UI, no repository/Riverpod dependency, no
/// presentation container of its own — the caller (MessageBubble, via
/// showFocusedActionMenu) owns how/where this list is displayed and all
/// mutation logic/error handling behind each callback.
///
/// [context] is used only for theming (the Delete tile's error color),
/// never to dismiss the menu: each tile pops via its OWN BuildContext,
/// obtained from a Builder placed inside the tile itself. That matters
/// because the context this function is called with belongs to the
/// long-press call site (MessageBubble), which in a real ChatScreen sits
/// inside a ListView that rebuilds while the overlay is open — by the
/// time an action is tapped that element can be deactivated, and
/// Navigator.of on a deactivated context throws "Looking up a
/// deactivated widget's ancestor is unsafe." Resolving from the tile's
/// own context instead always walks the live overlay tree and finds the
/// dialog route's navigator.
List<Widget> buildMessageActionItems({
  required BuildContext context,
  required Message message,
  required String currentUserId,
  required bool isStarred,
  required bool isPinned,
  required VoidCallback onReply,
  required VoidCallback onCopy,
  required VoidCallback onStar,
  required VoidCallback onUnstar,
  required VoidCallback onPin,
  required VoidCallback onUnpin,
  required VoidCallback onInfo,
  required VoidCallback onAskAttune,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  final canEditOrDelete = message.canEditOrDelete(
    currentUserId: currentUserId,
    now: DateTime.now(),
  );
  // AI Assistant spec §3's entry-eligibility gate, computed once here —
  // the same "compute once, pass down" shape canEditOrDelete already
  // uses — rather than an ad hoc check inline in the tile list below.
  final canAskAttune = message.isEligibleForAskAttune;
  final errorColor = Theme.of(context).colorScheme.error;

  /// Pops the menu using [tileContext] — the tile's own, always-live
  /// context — then runs the action.
  Widget item({
    required Widget leading,
    required String title,
    required VoidCallback onSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // The focused action menu design intentionally uses the app's legacy
    // onBackground + withOpacity token pairing here.
    // ignore: deprecated_member_use
    final titleColor = colorScheme.onBackground.withOpacity(
      OpacityTokens.medium,
    );

    return Builder(
      builder:
          (tileContext) => ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            minLeadingWidth: 24,
            horizontalTitleGap: 10,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: leading,
            title: Text(
              title,
              style: textTheme.bodyMedium?.copyWith(
                color: titleColor,
                fontSize: 14.sp,
              ),
            ),
            onTap: () {
              Navigator.of(tileContext).pop();
              onSelected();
            },
          ),
    );
  }

  final createdAt = message.createdAt;
  final now = DateTime.now();
  final isToday =
      createdAt.year == now.year &&
      createdAt.month == now.month &&
      createdAt.day == now.day;
  final timestampStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    height: 1.15,
  );
  final timestampHeader = Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child:
          isToday
              ? Text(
                'Today At ${MyDateFormat.toTime(createdAt)}',
                style: timestampStyle,
              )
              : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    MyDateFormat.toWeekdayMonth(createdAt),
                    style: timestampStyle,
                  ),
                  const SizedBox(height: 2),
                  Text(MyDateFormat.toTime(createdAt), style: timestampStyle),
                ],
              ),
    ),
  );

  return [
    timestampHeader,
    AppDivider(),
    item(
      leading: const Icon(Icons.reply_outlined),
      title: 'Reply',
      onSelected: onReply,
    ),
    item(
      leading: const Icon(Icons.copy_outlined),
      title: 'Copy',
      onSelected: onCopy,
    ),
    item(
      leading: const Icon(Icons.star_border),
      title: isStarred ? 'Unstar' : 'Star',
      onSelected: isStarred ? onUnstar : onStar,
    ),
    item(
      leading: const Icon(Icons.push_pin_outlined),
      title: isPinned ? 'Unpin' : 'Pin',
      onSelected: isPinned ? onUnpin : onPin,
    ),
    item(
      leading: const Icon(Icons.info_outline),
      title: 'Info',
      onSelected: onInfo,
    ),
    if (canAskAttune)
      item(
        leading: const Icon(Icons.auto_awesome_outlined),
        title: 'Ask Attune',
        onSelected: onAskAttune,
      ),
    if (canEditOrDelete) ...[
      item(
        leading: const Icon(Icons.edit_outlined),
        title: 'Edit',
        onSelected: onEdit,
      ),
      item(
        leading: Icon(Icons.delete_outline, color: errorColor),
        title: 'Delete',
        onSelected: onDelete,
      ),
    ],
  ];
}
