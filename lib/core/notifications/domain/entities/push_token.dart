// lib/features/notifications/domain/entities/push_token.dart

import 'package:equatable/equatable.dart';

/// Platform types for push notifications
enum PushTokenPlatform {
  ios,
  android,
  web;
  
  static PushTokenPlatform fromValue(String value) {
    switch (value.toLowerCase()) {
      case 'ios':
        return PushTokenPlatform.ios;
      case 'android':
        return PushTokenPlatform.android;
      case 'web':
        return PushTokenPlatform.web;
      default:
        return PushTokenPlatform.android;
    }
  }
  
  String get value => name;
}

/// Domain entity for device push tokens
class PushToken extends Equatable {
  final String id;
  final String userId;
  final String token;
  final PushTokenPlatform platform;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  const PushToken({
    required this.id,
    required this.userId,
    required this.token,
    required this.platform,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });
  
  @override
  List<Object?> get props => [id, userId, token, platform, isActive, createdAt, updatedAt];
}
