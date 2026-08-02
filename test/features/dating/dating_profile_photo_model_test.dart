import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DatingProfilePhoto.fromJson parses an approved photo', () {
    final photo = DatingProfilePhoto.fromJson({
      'id': 'photo-1',
      'position': 1,
      'moderation_state': 'approved',
      'rejection_reason': null,
      'storage_key': 'dating-photos/abc.jpg',
      'created_at': '2026-08-02T10:00:00Z',
    });

    expect(photo.id, 'photo-1');
    expect(photo.position, 1);
    expect(photo.isApproved, isTrue);
    expect(photo.isPending, isFalse);
    expect(photo.rejectionReason, isNull);
  });

  test('DatingProfilePhoto.fromJson parses a rejected photo with a reason', () {
    final photo = DatingProfilePhoto.fromJson({
      'id': 'photo-2',
      'position': 2,
      'moderation_state': 'rejected',
      'rejection_reason': 'face_blurred',
      'storage_key': 'dating-photos/def.jpg',
      'created_at': '2026-08-02T10:00:00Z',
    });

    expect(photo.isRejected, isTrue);
    expect(photo.rejectionReason, 'face_blurred');
  });

  test('DatingProfilePhoto.fromJson parses needs_review', () {
    final photo = DatingProfilePhoto.fromJson({
      'id': 'photo-3',
      'position': 3,
      'moderation_state': 'needs_review',
      'rejection_reason': 'no_face_detected',
      'storage_key': 'dating-photos/ghi.jpg',
      'created_at': '2026-08-02T10:00:00Z',
    });

    expect(photo.needsReview, isTrue);
    expect(photo.isApproved, isFalse);
  });
}
