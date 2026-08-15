import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current, active relationship's conversation only (0 or 1 entries —
/// see enforce_single_active_relationship in the schema). A user's chat
/// list is for the one relationship they're in right now — history from an
/// ended relationship is a distinct, deliberately separate surface (see
/// [previousConversationsProvider]), not another entry in this list. No
/// sort/search/unread-filter needed with at most one item to show.
final filteredConversationsProvider = Provider<List<Conversation>>((ref) {
  final conversationsAsync = ref.watch(conversationsProvider);

  // valueOrNull (not maybeWhen's data-only branch) so a background refresh
  // — including the one right behind conversationsProvider's own cache-then-
  // refresh instant paint — keeps showing the last-known list instead of
  // flashing to empty: AsyncLoading-with-a-previous-value has no `data`
  // case for maybeWhen to match, so it fell through to orElse's [] on every
  // refresh, even a cache hit.
  final conversations = conversationsAsync.valueOrNull ?? const [];
  return conversations.where((conversation) => conversation.canSend).toList();
});

/// Read-only conversations from relationships that have ended — surfaced
/// behind the "Previous relationships" card rather than mixed into the main
/// list, so the current relationship is never confused with history. Sorted
/// most-recently-active first; unaffected by unreadOnly/sort since read-only
/// threads have no unread state that matters and there's rarely more than a
/// couple of them.
final previousConversationsProvider = Provider<List<Conversation>>((ref) {
  final conversationsAsync = ref.watch(conversationsProvider);

  // valueOrNull, not maybeWhen — see filteredConversationsProvider above for
  // why: a background refresh must not flash this list to empty.
  final conversations = conversationsAsync.valueOrNull ?? const [];
  final previous =
      conversations.where((conversation) => !conversation.canSend).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return previous;
});
