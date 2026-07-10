// lib/features/notifications/domain/usecases/send_immediate_notification.dart

import 'package:equatable/equatable.dart';
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';

/// Parameters for sending immediate notification
class SendImmediateNotificationParams extends Equatable {
  final String userId;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final String priority;

  const SendImmediateNotificationParams({
    required this.userId,
    required this.title,
    required this.body,
    this.data,
    this.priority = 'normal',
  });

  @override
  List<Object?> get props => [userId, title, body, priority];
}

/// Use case for sending immediate push notifications
class SendImmediateNotificationUseCase {
  final NotificationRepositoryInterface repository;

  SendImmediateNotificationUseCase(this.repository);

  Future<void> call(SendImmediateNotificationParams params) async {
    await repository.queueImmediateNotification(
      userId: params.userId,
      title: params.title,
      body: params.body,
      data: params.data,
      priority: params.priority,
    );
  }
}
