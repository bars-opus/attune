import 'package:equatable/equatable.dart';

class DatingProfilePhoto extends Equatable {
  final String id;
  final int position;
  final String moderationState; // pending | approved | rejected | needs_review
  final String? rejectionReason;
  final String storageKey;
  final DateTime createdAt;

  const DatingProfilePhoto({
    required this.id,
    required this.position,
    required this.moderationState,
    this.rejectionReason,
    required this.storageKey,
    required this.createdAt,
  });

  factory DatingProfilePhoto.fromJson(Map<String, dynamic> json) {
    return DatingProfilePhoto(
      id: json['id'] as String,
      position: json['position'] as int,
      moderationState: json['moderation_state'] as String,
      rejectionReason: json['rejection_reason'] as String?,
      storageKey: json['storage_key'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isApproved => moderationState == 'approved';
  bool get isPending => moderationState == 'pending';
  bool get isRejected => moderationState == 'rejected';
  bool get needsReview => moderationState == 'needs_review';

  @override
  List<Object?> get props => [id, position, moderationState, rejectionReason, storageKey, createdAt];
}
