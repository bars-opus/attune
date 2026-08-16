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
