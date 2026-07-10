import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatChannelLoader extends ConsumerWidget {
  const ChatChannelLoader({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(chatRepositoryProvider).getConversation(relationshipId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final conversation = snapshot.data;
        if (conversation == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text('This conversation is unavailable.'),
            ),
          );
        }

        return ChatScreen(conversation: conversation);
      },
    );
  }
}
