import 'package:attune/core/widgets/feedback/empty_state.dart';
import 'package:attune/features/chat/presentation/screens/conversations_screen.dart';
import 'package:flutter/material.dart';

class ChatHomeScreen extends StatelessWidget {
  const ChatHomeScreen({super.key, required this.currentUserId});

  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    if (currentUserId.isEmpty) {
      return const Scaffold(
        body:  EmptyStateWidget(
            icon: Icons.chat,
            title: '',
            subtitle: 'Sign in to view your relationship chat.',
          ),
        
       
      );
    }

    return const ConversationsScreen();
  }
}
