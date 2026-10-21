import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatConfig {
  final String conversationsTitle;
  final int messagePageSize;

  /// Page size while paging back to a jump target (reply quote, pin,
  /// Starred). Larger than messagePageSize because the person is waiting on
  /// it.
  final int jumpPageSize;
  final int maxCachedMessages;
  final Duration networkTimeout;
  final Duration controllerKeepAlive;

  /// Longest a chat left with a send in flight keeps its controller (M7).
  /// Past it the controller goes even mid-send: the send is durable in the
  /// outbox and resumes on the next open or drainer pass, so a request the
  /// network black-holed can never pin the realtime channel forever.
  final Duration controllerKeepAliveCeiling;
  final Duration realtimeRefreshDebounce;
  final int notificationPreviewMaxLength;

  final Widget Function(BuildContext context, String title)? headerBuilder;

  const ChatConfig({
    this.conversationsTitle = 'Chat',
    this.messagePageSize = 50,
    this.jumpPageSize = 200,
    this.maxCachedMessages = 200,
    this.networkTimeout = const Duration(seconds: 20),
    this.controllerKeepAlive = const Duration(minutes: 5),
    this.controllerKeepAliveCeiling = const Duration(minutes: 30),
    this.realtimeRefreshDebounce = const Duration(milliseconds: 250),
    this.notificationPreviewMaxLength = 0,
    this.headerBuilder,
  });
}

final chatConfigProvider = Provider<ChatConfig>((ref) => const ChatConfig());
