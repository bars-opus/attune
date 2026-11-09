import 'package:equatable/equatable.dart';

/// A Dating photo of the signed-in person (§3.2 D9; positions 1-6). Reads
/// the v2 list's keys (`state`, `reason`, `caption`) and the v1 ones.
class DatingProfilePhoto extends Equatable {
  final String id;
  final int position;
  final String moderationState; // pending | approved | rejected | needs_review
  final String?
  rejectionReason; // face_unclear | too_small | contains_child | unsafe | needs_review
  final String? caption;
  final String storageKey;
  final DateTime createdAt;

  const DatingProfilePhoto({
    required this.id,
    required this.position,
    required this.moderationState,
    this.rejectionReason,
    this.caption,
    required this.storageKey,
    required this.createdAt,
  });

  factory DatingProfilePhoto.fromJson(Map<String, dynamic> json) {
    return DatingProfilePhoto(
      id: json['id'] as String,
      position: json['position'] as int,
      moderationState: (json['state'] ?? json['moderation_state']) as String,
      rejectionReason: (json['reason'] ?? json['rejection_reason']) as String?,
      caption: json['caption'] as String?,
      storageKey: json['storage_key'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isApproved => moderationState == 'approved';
  bool get isPending => moderationState == 'pending';
  bool get isRejected => moderationState == 'rejected';
  bool get needsReview => moderationState == 'needs_review';

  /// Never printed (T10): a caption is the person's own words, and a
  /// storage key names their object.
  @override
  bool get stringify => false;

  @override
  List<Object?> get props => [
    id,
    position,
    moderationState,
    rejectionReason,
    caption,
    storageKey,
    createdAt,
  ];
}
