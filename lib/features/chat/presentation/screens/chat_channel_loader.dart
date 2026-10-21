import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/widgets/feedback/empty_state.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ChatChannelLoader extends ConsumerStatefulWidget {
  const ChatChannelLoader({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  ConsumerState<ChatChannelLoader> createState() => _ChatChannelLoaderState();
}

class _ChatChannelLoaderState extends ConsumerState<ChatChannelLoader> {
  // Fetched once per screen, not per build: a rebuild must not refetch and
  // flash the spinner again.
  late final Future<Conversation?> _conversation = ref
      .read(chatRepositoryProvider)
      .getConversation(widget.relationshipId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Conversation?>(
      future: _conversation,
      builder: (context, snapshot) {
        // Only a load still in flight spins. A null result (not a member,
        // or the chat is gone) and an error both used to fall through
        // `!snapshot.hasData` and spin forever with no way out.
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final conversation = snapshot.data;
        if (snapshot.hasError || conversation == null) {
          if (snapshot.hasError) {
            ChatLog.e('chat channel load failed', snapshot.error);
          }
          return const _ConversationUnavailable();
        }

        return ChatScreen(conversation: conversation);
      },
    );
  }
}

/// The final state for a chat this person cannot open. Says so plainly and
/// always offers a way out, even when the screen was opened from a
/// notification with nothing beneath it to pop back to.
class _ConversationUnavailable extends StatelessWidget {
  const _ConversationUnavailable();

  void _leave(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    GoRouter.maybeOf(context)?.go(RouteNames.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: EmptyStateWidget(
          type: EmptyStateType.custom,
          icon: Icons.forum_outlined,
          title: "This conversation isn't available",
          subtitle: "It may have ended, or it can't be reached right now.",
          actionLabel: 'Go back',
          onAction: () => _leave(context),
          compact: false,
        ),
      ),
    );
  }
}
