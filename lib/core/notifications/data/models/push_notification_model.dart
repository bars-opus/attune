// lib/features/notifications/data/models/push_notification_model.dart

/// Model for push notification queue
class PushNotificationQueueModel {
  final String? id;
  final String userId;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String priority;
  final String status;
  final DateTime createdAt;
  final DateTime? sentAt;
  final String? error;
  
  PushNotificationQueueModel({
    this.id,
    required this.userId,
    required this.title,
    required this.body,
    this.data = const {},
    this.priority = 'normal',
    this.status = 'pending',
    required this.createdAt,
    this.sentAt,
    this.error,
  });
  
  factory PushNotificationQueueModel.fromJson(Map<String, dynamic> json) {
    return PushNotificationQueueModel(
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      data: json['data'] as Map<String, dynamic>? ?? {},
      priority: json['priority'] as String? ?? 'normal',
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
      sentAt: json['sent_at'] != null ? DateTime.parse(json['sent_at'] as String) : null,
      error: json['error'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'title': title,
      'body': body,
      'data': data,
      'priority': priority,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      if (sentAt != null) 'sent_at': sentAt!.toIso8601String(),
      if (error != null) 'error': error,
    };
  }
}
