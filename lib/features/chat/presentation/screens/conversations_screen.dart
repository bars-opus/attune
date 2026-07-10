import 'package:attune/app/routing/app_router.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/providers/chat_ui_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/healing/presentation/screens/healing_journey_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final filtered = ref.watch(filteredConversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            onPressed: () => _openReflections(context),
            icon: const Icon(Icons.self_improvement_outlined),
            tooltip: 'Personal reflections',
          ),
          IconButton(
            onPressed: () {
              ref.read(unreadOnlyProvider.notifier).state =
                  !ref.read(unreadOnlyProvider);
            },
            icon: Icon(
              ref.watch(unreadOnlyProvider)
                  ? Icons.mark_chat_unread
                  : Icons.mark_chat_unread_outlined,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged:
                  (value) =>
                      ref.read(searchQueryProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: conversationsAsync.when(
              data: (_) {
                if (filtered.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    children: [
                      _ReflectionCard(onTap: () => _openReflections(context)),
                      const SizedBox(height: 24),
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No relationship chat is available yet.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    _ReflectionCard(onTap: () => _openReflections(context)),
                    const SizedBox(height: 12),
                    for (var index = 0; index < filtered.length; index++) ...[
                      _ConversationCard(
                        conversation: filtered[index],
                        previewText: _previewText(filtered[index]),
                        onTap:
                            () => _openConversation(context, filtered[index]),
                      ),
                      if (index != filtered.length - 1)
                        const SizedBox(height: 8),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (_, __) => Center(
                    child: TextButton(
                      onPressed:
                          () =>
                              ref
                                  .read(conversationsRefreshProvider.notifier)
                                  .state++,
                      child: const Text('Reload chat'),
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  void _openConversation(BuildContext context, Conversation conversation) {
    context.push(RouteNames.chatScreen, extra: conversation);
  }

  void _openReflections(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HealingJourneyScreen()),
    );
  }

  String _previewText(Conversation conversation) {
    final message = conversation.lastMessage;
    if (message == null) return 'No messages yet';
    if (message.mediaType == 'image' && message.content.trim().isEmpty) {
      return 'Photo';
    }
    if (message.mediaType == 'image' && message.content.trim().isNotEmpty) {
      return 'Photo: ${message.content}';
    }
    return message.content;
  }
}

class _ReflectionCard extends StatelessWidget {
  const _ReflectionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.secondaryContainer,
                child: Icon(
                  Icons.self_improvement_outlined,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personal reflections',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A private space for your own reflection work. This never sends messages to your partner.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.conversation,
    required this.previewText,
    required this.onTap,
  });

  final Conversation conversation;
  final String previewText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              conversation.avatarUrl == null
                  ? null
                  : NetworkImage(conversation.avatarUrl!),
          child:
              conversation.avatarUrl == null
                  ? Text(_initialForName(conversation.name))
                  : null,
        ),
        title: Row(
          children: [
            Expanded(child: Text(conversation.name)),
            if (conversation.unreadCount > 0)
              CircleAvatar(
                radius: 12,
                backgroundColor: colorScheme.primary,
                child: Text(
                  conversation.unreadCount > 99
                      ? '99+'
                      : '${conversation.unreadCount}',
                  style: TextStyle(fontSize: 12, color: colorScheme.onPrimary),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(previewText, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _StatusPill(
                  label: conversation.relationshipStatus,
                  icon:
                      conversation.canSend
                          ? Icons.favorite_outline
                          : Icons.lock_outline,
                ),
                if (conversation.isArchived)
                  const _StatusPill(
                    label: 'Archived',
                    icon: Icons.archive_outlined,
                  )
                else if (!conversation.canSend)
                  const _StatusPill(
                    label: 'Read-only',
                    icon: Icons.pause_circle_outline,
                  ),
              ],
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

String _initialForName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'P';
  return trimmed.characters.first.toUpperCase();
}
