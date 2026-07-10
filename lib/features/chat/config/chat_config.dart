import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatConfig {
  final String conversationsTitle;
  final int messagePageSize;
  final int maxCachedMessages;
  final Duration networkTimeout;
  final Duration controllerKeepAlive;
  final Duration realtimeRefreshDebounce;
  final int notificationPreviewMaxLength;

  final Widget Function(BuildContext context, String title)? headerBuilder;

  const ChatConfig({
    this.conversationsTitle = 'Chat',
    this.messagePageSize = 50,
    this.maxCachedMessages = 200,
    this.networkTimeout = const Duration(seconds: 20),
    this.controllerKeepAlive = const Duration(minutes: 5),
    this.realtimeRefreshDebounce = const Duration(milliseconds: 250),
    this.notificationPreviewMaxLength = 0,
    this.headerBuilder,
  });
}

final chatConfigProvider = Provider<ChatConfig>((ref) => const ChatConfig());
