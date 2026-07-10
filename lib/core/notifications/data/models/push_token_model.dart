// lib/features/notifications/data/models/push_token_model.dart
import 'package:attune/core/notifications/domain/entities/push_token.dart';

/// Model for push tokens
class PushTokenModel {
  final String? id;
  final String userId;
  final String token;
  final String platform;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  PushTokenModel({
    this.id,
    required this.userId,
    required this.token,
    required this.platform,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });
  
  factory PushTokenModel.fromJson(Map<String, dynamic> json) {
    return PushTokenModel(
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      token: json['token'] as String,
      platform: json['platform'] as String,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'token': token,
      'platform': platform,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
  
  PushToken toDomain() {
    return PushToken(
      id: id!,
      userId: userId,
      token: token,
      platform: PushTokenPlatform.fromValue(platform),
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
  
  factory PushTokenModel.fromDomain(PushToken token) {
    return PushTokenModel(
      id: token.id,
      userId: token.userId,
      token: token.token,
      platform: token.platform.value,
      isActive: token.isActive,
      createdAt: token.createdAt,
      updatedAt: token.updatedAt,
    );
  }
}
