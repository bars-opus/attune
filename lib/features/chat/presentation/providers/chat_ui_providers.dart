import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

enum SortCriteria {
  recent('Most Recent'),
  unread('Unread First'),
  alphabetical('A-Z');

  final String label;
  const SortCriteria(this.label);
}

final sortCriteriaProvider = StateProvider<SortCriteria>(
  (ref) => SortCriteria.recent,
);

final unreadOnlyProvider = StateProvider<bool>((ref) => false);

final filteredConversationsProvider = Provider<List<Conversation>>((ref) {
  final conversationsAsync = ref.watch(conversationsProvider);
  final searchQuery = ref.watch(searchQueryProvider).trim().toLowerCase();
  final sort = ref.watch(sortCriteriaProvider);
  final unreadOnly = ref.watch(unreadOnlyProvider);

  return conversationsAsync.maybeWhen(
    data: (conversations) {
      var filtered =
          conversations.where((conversation) {
            if (unreadOnly && conversation.unreadCount == 0) return false;
            if (searchQuery.isEmpty) return true;

            final matchesName = conversation.name.toLowerCase().contains(
              searchQuery,
            );
            final matchesPreview =
                conversation.lastMessage?.content.toLowerCase().contains(
                  searchQuery,
                ) ??
                false;
            return matchesName || matchesPreview;
          }).toList();

      switch (sort) {
        case SortCriteria.recent:
          filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          break;
        case SortCriteria.unread:
          filtered.sort((a, b) {
            final unreadRank = b.unreadCount.compareTo(a.unreadCount);
            if (unreadRank != 0) return unreadRank;
            return b.updatedAt.compareTo(a.updatedAt);
          });
          break;
        case SortCriteria.alphabetical:
          filtered.sort((a, b) => a.name.compareTo(b.name));
          break;
      }
      return filtered;
    },
    orElse: () => const [],
  );
});
