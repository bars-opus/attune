import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PendingSend toJson/fromJson round-trips the four new video fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      localMediaPath: '/tmp/clip.mp4',
      mediaMimeType: 'video/mp4',
      mediaType: 'video',
      mediaDurationMs: 12000,
      localThumbnailPath: '/tmp/poster.jpg',
      thumbnailMimeType: 'image/jpeg',
      mediaWidth: 1280,
      mediaHeight: 720,
      createdAt: DateTime(2026, 8, 15, 9),
    );

    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.localThumbnailPath, '/tmp/poster.jpg');
    expect(restored.thumbnailMimeType, 'image/jpeg');
    expect(restored.mediaWidth, 1280);
    expect(restored.mediaHeight, 720);
  });

  test('PendingSend.copyWith preserves the four new video fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      mediaType: 'video',
      localThumbnailPath: '/tmp/poster.jpg',
      thumbnailMimeType: 'image/jpeg',
      mediaWidth: 1280,
      mediaHeight: 720,
      createdAt: DateTime(2026, 8, 15, 9),
    );
    final copied = original.copyWith(state: PendingSendState.sending);
    expect(copied.localThumbnailPath, '/tmp/poster.jpg');
    expect(copied.thumbnailMimeType, 'image/jpeg');
    expect(copied.mediaWidth, 1280);
    expect(copied.mediaHeight, 720);
  });

  test('a non-video PendingSend has null video fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: 'hi',
      createdAt: DateTime(2026, 8, 15, 9),
    );
    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.localThumbnailPath, isNull);
    expect(restored.thumbnailMimeType, isNull);
    expect(restored.mediaWidth, isNull);
    expect(restored.mediaHeight, isNull);
  });

  test('preparation metadata survives an outbox round-trip', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      localMediaPath: '/tmp/raw.mov',
      mediaType: 'video',
      requiresPreparation: true,
      trimStartMs: 1250,
      trimEndMs: 9250,
      createdAt: DateTime(2026, 8, 15, 9),
    );

    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.requiresPreparation, isTrue);
    expect(restored.trimStartMs, 1250);
    expect(restored.trimEndMs, 9250);
  });

  test('completed upload keys survive retry and process restart', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      localMediaPath: '/tmp/clip.mp4',
      mediaMimeType: 'video/mp4',
      mediaType: 'video',
      uploadedMediaKey: 'message-media/r1/video.mp4',
      uploadedThumbnailKey: 'message-media/r1/poster.jpg',
      createdAt: DateTime(2026, 8, 15, 9),
    );

    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.uploadedMediaKey, 'message-media/r1/video.mp4');
    expect(restored.uploadedThumbnailKey, 'message-media/r1/poster.jpg');

    final retrying = restored.copyWith(state: PendingSendState.sending);
    expect(retrying.uploadedMediaKey, restored.uploadedMediaKey);
    expect(retrying.uploadedThumbnailKey, restored.uploadedThumbnailKey);
  });

  test('copyWith can finish preparation and clear retry metadata', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      localMediaPath: '/tmp/raw.mov',
      mediaType: 'video',
      requiresPreparation: true,
      trimStartMs: 1250,
      trimEndMs: 9250,
      nextAttemptAt: DateTime(2026, 8, 15, 10),
      lastErrorCategory: 'media_decode_failed',
      createdAt: DateTime(2026, 8, 15, 9),
    );

    final prepared = original.copyWith(
      localMediaPath: '/tmp/prepared.mp4',
      mediaMimeType: 'video/mp4',
      localThumbnailPath: '/tmp/poster.jpg',
      thumbnailMimeType: 'image/jpeg',
      mediaDurationMs: 8000,
      mediaWidth: 720,
      mediaHeight: 1280,
      requiresPreparation: false,
      nextAttemptAt: null,
      lastErrorCategory: null,
    );

    expect(prepared.localMediaPath, '/tmp/prepared.mp4');
    expect(prepared.mediaMimeType, 'video/mp4');
    expect(prepared.localThumbnailPath, '/tmp/poster.jpg');
    expect(prepared.requiresPreparation, isFalse);
    expect(prepared.nextAttemptAt, isNull);
    expect(prepared.lastErrorCategory, isNull);
  });

  test('PendingSend toJson/fromJson round-trips isViewOnce', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      localMediaPath: '/tmp/clip.mp4',
      mediaMimeType: 'video/mp4',
      mediaType: 'video',
      mediaDurationMs: 8000,
      localThumbnailPath: '/tmp/poster.jpg',
      thumbnailMimeType: 'image/jpeg',
      mediaWidth: 720,
      mediaHeight: 1280,
      isViewOnce: true,
      createdAt: DateTime(2026, 8, 16, 9),
    );
    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.isViewOnce, isTrue);
  });

  test('PendingSend.copyWith preserves isViewOnce', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      mediaType: 'video',
      isViewOnce: true,
      createdAt: DateTime(2026, 8, 16, 9),
    );
    final copied = original.copyWith(state: PendingSendState.sending);
    expect(copied.isViewOnce, isTrue);
  });

  test('isViewOnce defaults to false for a non-ephemeral PendingSend', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      mediaType: 'video',
      createdAt: DateTime(2026, 8, 16, 9),
    );
    expect(original.isViewOnce, isFalse);
    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.isViewOnce, isFalse);
  });
}
