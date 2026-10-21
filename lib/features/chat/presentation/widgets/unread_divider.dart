import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/chat_date_chip.dart';
import 'package:flutter/material.dart';

/// Whether [message] is one the server counts as unread for the viewer:
/// the partner's, not a system notice, not deleted — matching
/// count_unread_messages. Also what the scroll-to-newest pill counts.
bool countsTowardUnread(Message message) =>
    !message.isMine && !message.isSystemNotice && !message.isDeleted;

/// Where the "N unread messages" divider sits: ABOVE [messageId].
class UnreadDividerPlacement {
  const UnreadDividerPlacement({
    required this.messageId,
    required this.unplaced,
  });

  /// The row the divider sits above.
  final String messageId;

  /// Unread partner messages still older than the loaded window (the count
  /// was larger than what the first page held). 0 once the divider is on
  /// the oldest unread message itself.
  final int unplaced;
}

/// Places the divider from the first settled page: above the
/// [unreadCount]-th newest message that [countsTowardUnread]. When fewer
/// such rows are loaded, above the oldest loaded one, so the divider still
/// marks "everything from here down is new" (with the true count). Null
/// when [unreadCount] <= 0 or no such row is loaded.
///
/// [sentBy] is the moment the count was taken (the chat's open): a row the
/// server stamped after it arrived later and is not among the counted ones,
/// so it is skipped — what keeps a divider placed late (after an offline
/// open) from sliding down onto rows the count never meant.
UnreadDividerPlacement? placeUnreadDivider(
  List<Message> newestFirst,
  int unreadCount, {
  DateTime? sentBy,
}) {
  if (unreadCount <= 0) return null;
  String? candidate;
  var seen = 0;
  for (final message in newestFirst) {
    if (!countsTowardUnread(message)) continue;
    if (sentBy != null && message.sortAt.isAfter(sentBy)) continue;
    candidate = message.id;
    seen++;
    if (seen == unreadCount) break;
  }
  if (candidate == null) return null;
  return UnreadDividerPlacement(
    messageId: candidate,
    unplaced: unreadCount - seen,
  );
}

/// Moves a short [placement] further back once older history has loaded:
/// counts only rows OLDER than its current row, so messages that arrived
/// at the newest end since the chat opened can never pull it down. Returns
/// [placement] unchanged when it is complete or its row is gone.
UnreadDividerPlacement extendUnreadDivider(
  List<Message> newestFirst,
  UnreadDividerPlacement placement,
) {
  if (placement.unplaced <= 0) return placement;
  final from = newestFirst.indexWhere((m) => m.id == placement.messageId);
  if (from < 0) return placement;
  var candidate = placement.messageId;
  var remaining = placement.unplaced;
  for (var i = from + 1; i < newestFirst.length && remaining > 0; i++) {
    final message = newestFirst[i];
    if (!countsTowardUnread(message)) continue;
    candidate = message.id;
    remaining--;
  }
  if (candidate == placement.messageId) return placement;
  return UnreadDividerPlacement(messageId: candidate, unplaced: remaining);
}

/// The id of the row the divider sits ABOVE (see [placeUnreadDivider]).
String? unreadDividerMessageId(List<Message> newestFirst, int unreadCount) =>
    placeUnreadDivider(newestFirst, unreadCount)?.messageId;

/// The divider's copy — one plural function, so it maps 1:1 onto an ICU
/// plural when chat strings are extracted.
String unreadDividerLabel(int count) =>
    count == 1 ? '1 unread message' : '$count unread messages';

/// Same rule-and-pill grammar as ChatDateSeparator, so it reads as part of
/// the list rather than a banner.
class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rule = Expanded(
      child: Container(
        height: 0.6,
        color: colorScheme.primary.withValues(alpha: 0.35),
      ),
    );
    return Padding(
      key: const ValueKey('chat_unread_divider'),
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          rule,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
            child: ChatDateChip(label: unreadDividerLabel(count)),
          ),
          rule,
        ],
      ),
    );
  }
}
