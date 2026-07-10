import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Account types supported by the app
enum AccountType {
  client('client', 'Client', Icons.person_outline),
  shop('shop', 'Shop Owner', Icons.store_outlined),
  worker('worker', 'Worker', Icons.badge_outlined);

  const AccountType(this.value, this.displayName, this.icon);

  final String value;
  final String displayName;
  final IconData icon;

  static AccountType fromString(String value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => client,
    );
  }
}

/// User role model
class UserRole extends Equatable {
  final String id;
  final String userId;
  final AccountType role;
  final bool isActive;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserRole({
    required this.id,
    required this.userId,
    required this.role,
    this.isActive = true,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserRole.fromJson(Map<String, dynamic> json) {
    return UserRole(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      role: AccountType.fromString(json['role'] as String),
      isActive: json['is_active'] as bool? ?? true,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'role': role.value,
      'is_active': isActive,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, userId, role, isActive];
}
