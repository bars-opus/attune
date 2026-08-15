import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMediaUploadIntent', () {
    test('is constructible with the same fields regardless of media type', () {
      // Regression guard for the createImageUploadIntent -> createMediaUploadIntent
      // generalization: ChatMediaUploadIntent itself must stay media-type-agnostic
      // (no new image-only or audio-only field creeps in during the rename).
      final imageIntent = ChatMediaUploadIntent(
        intentId: 'i1',
        storageKey: 'chat-media/a.jpg',
        expiresAt: DateTime(2026, 8, 15, 12),
        bucket: 'message-media',
      );
      final audioIntent = ChatMediaUploadIntent(
        intentId: 'i2',
        storageKey: 'chat-media/b.m4a',
        expiresAt: DateTime(2026, 8, 15, 12),
        bucket: 'message-media',
      );
      expect(imageIntent.bucket, audioIntent.bucket);
      expect(imageIntent.runtimeType, audioIntent.runtimeType);
    });
  });
}
