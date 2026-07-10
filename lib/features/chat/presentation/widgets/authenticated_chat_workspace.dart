import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/screens/chat_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthenticatedChatWorkspace extends ConsumerWidget {
  const AuthenticatedChatWorkspace({
    super.key,
    required this.isCouples,
    required this.isPendingCouples,
  });

  final bool isCouples;
  final bool isPendingCouples;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserProvider)?.id ?? '';

    if (userId.isEmpty) {
      return const Center(child: Text('Sign in to access chat.'));
    }

    if (!isCouples) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isPendingCouples
                ? 'Your relationship invite is still pending. Chat unlocks when both partners are connected.'
                : 'Chat is available in Couples mode.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ChatHomeScreen(currentUserId: userId);
  }
}
