import 'package:attune/features/chat/presentation/screens/conversations_screen.dart';
import 'package:flutter/material.dart';

class ChatHomeScreen extends StatelessWidget {
  const ChatHomeScreen({super.key, required this.currentUserId});

  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    if (currentUserId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Sign in to view your relationship chat.')),
      );
    }

    return const ConversationsScreen();
  }
}
