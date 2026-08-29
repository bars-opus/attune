import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';

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
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  final canEditOrDelete = message.canEditOrDelete(
    currentUserId: currentUserId,
    now: DateTime.now(),
  );
  final errorColor = Theme.of(context).colorScheme.error;

  /// Pops the menu using [tileContext] — the tile's own, always-live
  /// context — then runs the action.
  Widget item({
    required Widget leading,
    required Widget title,
    required VoidCallback onSelected,
  }) {
    return Builder(
      builder:
          (tileContext) => ListTile(
            leading: leading,
            title: title,
            onTap: () {
              Navigator.of(tileContext).pop();
              onSelected();
            },
          ),
    );
  }

  return [
    item(
      leading: const Icon(Icons.reply),
      title: const Text('Reply'),
      onSelected: onReply,
    ),
    item(
      leading: const Icon(Icons.copy),
      title: const Text('Copy'),
      onSelected: onCopy,
    ),
    item(
      leading: Icon(isStarred ? Icons.star : Icons.star_border),
      title: Text(isStarred ? 'Unstar' : 'Star'),
      onSelected: isStarred ? onUnstar : onStar,
    ),
    item(
      leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
      title: Text(isPinned ? 'Unpin' : 'Pin'),
      onSelected: isPinned ? onUnpin : onPin,
    ),
    if (canEditOrDelete) ...[
      item(
        leading: const Icon(Icons.edit),
        title: const Text('Edit'),
        onSelected: onEdit,
      ),
      item(
        leading: Icon(Icons.delete, color: errorColor),
        title: Text('Delete', style: TextStyle(color: errorColor)),
        onSelected: onDelete,
      ),
    ],
  ];
}
