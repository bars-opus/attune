// lib/features/notifications/domain/entities/notification.dart

import 'package:equatable/equatable.dart';

/// Domain entity representing a notification
class AppNotification extends Equatable {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;
  
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.data,
    this.isRead = false,
    this.readAt,
    required this.createdAt,
  });
  
  @override
  List<Object?> get props => [id, title, body, isRead, createdAt];
  
  /// Create a copy with updated fields
  AppNotification copyWith({
    String? id,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    bool? isRead,
    DateTime? readAt,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
