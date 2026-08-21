import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
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
  const StarredMessagesScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final starredAsync = ref.watch(starredMessagesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
              child: EmptyStateWidget(
                title: '',
                subtitle: 'No starred messages yet.',
                icon: Icons.star_border,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(Spacing.md),
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final message = messages[index];
              return InfoRowWidget(
                title:
                    message.isDeleted
                        ? 'This message was deleted'
                        : message.content,
                subtitle: DateFormat.yMMMd().add_jm().format(message.createdAt),
                icon: Icons.star_border,
                showAvatar: false,

                showDivider: true,
                onTap:
                    message.isDeleted
                        ? null
                        : () => context.push(
                          '${RouteNames.chatScreen}?jumpTo=${message.id}',
                          extra: conversation,
                        ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) => Center(
              child: ErrorStateWidget(
                title: '',
                subtitle: "Couldn't load starred messages.",
              ),
            ),
      ),
    );
  }
}
