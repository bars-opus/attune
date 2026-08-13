import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';

/// WhatsApp-style long-press action sheet for a chat message bubble.
/// Pure UI — takes callbacks, has no repository/Riverpod dependency, so
/// it's trivially testable and the caller (ChatScreen) owns all mutation
/// logic and error handling. Edit/Delete are omitted (not shown-disabled)
/// once [Message.canEditOrDelete] is false, matching the design spec's
/// "no dead menu item that invites a confused tap" decision.
Future<void> showMessageActionsSheet({
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

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onReply();
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onCopy();
                },
              ),
              ListTile(
                leading: Icon(isStarred ? Icons.star : Icons.star_border),
                title: Text(isStarred ? 'Unstar' : 'Star'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  isStarred ? onUnstar() : onStar();
                },
              ),
              ListTile(
                leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                title: Text(isPinned ? 'Unpin' : 'Pin'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  isPinned ? onUnpin() : onPin();
                },
              ),
              if (canEditOrDelete) ...[
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onEdit();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete, color: Theme.of(sheetContext).colorScheme.error),
                  title: Text(
                    'Delete',
                    style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onDelete();
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
