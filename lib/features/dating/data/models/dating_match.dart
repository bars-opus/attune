// lib/features/dating/data/models/dating_match.dart

import 'package:equatable/equatable.dart';

class DatingMatch extends Equatable {
  final String id;
  final String introductionId;
  final String userLowId;
  final String userHighId;
  final String state; // 'active', 'closed', 'unmatched', 'blocked'
  final DateTime matchedAt;
  final DateTime? closedAt;
  final DateTime createdAt;

  const DatingMatch({
    required this.id,
    required this.introductionId,
    required this.userLowId,
    required this.userHighId,
    required this.state,
    required this.matchedAt,
    this.closedAt,
    required this.createdAt,
  });

  factory DatingMatch.fromJson(Map<String, dynamic> json) {
    return DatingMatch(
      id: json['id'],
      introductionId: json['introduction_id'],
      userLowId: json['user_low_id'],
      userHighId: json['user_high_id'],
      state: json['state'],
      matchedAt: DateTime.parse(json['matched_at']),
      closedAt:
          json['closed_at'] != null ? DateTime.parse(json['closed_at']) : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  bool get isActive => state == 'active';
  bool get isUnmatched => state == 'unmatched';
  bool get isClosed => state == 'closed';

  String otherUserIdFor(String currentUserId) {
    if (currentUserId == userLowId) return userHighId;
    if (currentUserId == userHighId) return userLowId;
    throw ArgumentError('Current user is not a member of this match.');
  }

  @override
  List<Object?> get props => [
    id,
    introductionId,
    userLowId,
    userHighId,
    state,
    matchedAt,
    closedAt,
    createdAt,
  ];
}
