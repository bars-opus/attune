import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final starredMessagesProvider = FutureProvider<List<Message>>((ref) async {
  final repository = ref.watch(chatRepositoryProvider);
  return repository.getStarredMessages();
});

/// Private per-user list — never shows the partner's starred messages
/// (message_stars RLS is owner-only; see
/// docs/superpowers/specs/2026-08-13-message-actions-design.md decision 5).
class StarredMessagesScreen extends ConsumerWidget {
  const StarredMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final starredAsync = ref.watch(starredMessagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Starred messages',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
      body: starredAsync.when(
        data: (messages) {
          if (messages.isEmpty) {
            return Center(
              child: Text(
                'No starred messages yet.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final message = messages[index];
              return ListTile(
                leading: Icon(Icons.star, color: colorScheme.primary),
                title: Text(
                  message.isDeleted
                      ? 'This message was deleted'
                      : message.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      message.isDeleted
                          ? textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: colorScheme.onSurfaceVariant,
                          )
                          : textTheme.bodyMedium,
                ),
                subtitle: Text(
                  DateFormat.yMMMd().add_jm().format(message.createdAt),
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) => Center(
              child: Text(
                "Couldn't load starred messages.",
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
      ),
    );
  }
}
