import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/screens/chat_couples_locked_screen.dart';
import 'package:attune/features/chat/presentation/screens/chat_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthenticatedChatWorkspace extends ConsumerWidget {
  const AuthenticatedChatWorkspace({
    super.key,
    required this.isCouples,
    required this.isPendingCouples,
    required this.onInviteSent,
  });

  final bool isCouples;
  final bool isPendingCouples;

  /// Bubbled up to HomeScreen (see its doc) so the app shell can reload the
  /// OnboardingStore and re-route once a personal-mode user generates a
  /// partner invite and moves onto the couplesPending track.
  final VoidCallback onInviteSent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserProvider)?.id ?? '';

    if (userId.isEmpty) {
      return const Center(child: Text('Sign in to access chat.'));
    }

    if (!isCouples) {
      return ChatCouplesLockedScreen(
        isPendingCouples: isPendingCouples,

        onInviteSent: onInviteSent,
      );
    }

    return ChatHomeScreen(currentUserId: userId);
  }
}
