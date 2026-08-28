import 'package:attune/app/routing/app_router.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/providers/chat_ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:attune/features/chat/domain/utils/conversation_preview.dart';

/// Read-only history: relationships that have ended, each still reachable
/// as a read-only thread. Kept off the main Chat tab (see
/// previousConversationsProvider's doc) so the current relationship is
/// never confused with an ex's.
class PreviousRelationshipsScreen extends ConsumerWidget {
  const PreviousRelationshipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final previous = ref.watch(previousConversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Previous relationships',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
      body:
          previous.isEmpty
              ? const Center(child: Text('No previous relationships.'))
              : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: previous.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final conversation = previous[index];
                  return _PreviousConversationCard(
                    conversation: conversation,
                    previewText: _previewText(conversation),
                    onTap: () => _openConversation(context, conversation),
                  );
                },
              ),
    );
  }

  void _openConversation(BuildContext context, Conversation conversation) {
    context.push(RouteNames.chatScreen, extra: conversation);
  }

  String _previewText(Conversation conversation) =>
      conversationPreviewText(conversation);
}

class _PreviousConversationCard extends StatelessWidget {
  const _PreviousConversationCard({
    required this.conversation,
    required this.previewText,
    required this.onTap,
  });

  final Conversation conversation;
  final String previewText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
        title: Text(conversation.name),
        subtitle: Text(
          previewText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.lock_outline, size: 18),
        onTap: onTap,
      ),
    );
  }
}

String _initialForName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'P';
  return trimmed.characters.first.toUpperCase();
}
