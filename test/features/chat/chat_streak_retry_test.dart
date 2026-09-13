import 'dart:io';

import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _FailOnceStreakRepository extends StreakRepository {
  int calls = 0;

  @override
  Future<void> attachClip({
    required String messageId,
    required String mediaUrl,
    required int durationMs,
    StreakClipKind mediaKind = StreakClipKind.video,
  }) async {
    calls++;
    if (calls == 1) throw Exception('connection dropped before clip attach');
  }
}

void main() {
  test(
    'retry completes a missing streak clip without reuploading media',
    () async {
      final temp = await Directory.systemTemp.createTemp('streak_retry_test');
      addTearDown(() => temp.delete(recursive: true));
      final clip = File('${temp.path}/clip.mp4');
      await clip.writeAsBytes(List<int>.filled(128, 1));

      final repo = FakeChatRepository(currentUserId: 'user-a');
      final streaks = _FailOnceStreakRepository();
      final conversation = activeConversation('rel-1');
      repo.conversationOverride = conversation;
      final container = buildChatContainer(
        repository: repo,
        userId: 'user-a',
        extraOverrides: [streakRepositoryProvider.overrideWithValue(streaks)],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        chatControllerProvider(conversation).notifier,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.sendStreakMessage(
        localPath: clip.path,
        durationMs: 3000,
        viewsRemaining: 1,
      );

      final queued =
          container.read(chatControllerProvider(conversation)).messages.single;
      expect(queued.status, MessageStatus.queued);
      expect(streaks.calls, 1);
      expect(repo.mediaCallCount, 2);

      // The message row already committed before the first clip attach failed,
      // so the real database answers the retry with its idempotency conflict.
      repo
        ..simulateDuplicate = true
        ..duplicateClientMessageId = queued.clientMessageId;
      await controller.retryMessage(queued);

      final recovered =
          container.read(chatControllerProvider(conversation)).messages.single;
      expect(recovered.status, MessageStatus.sent);
      expect(streaks.calls, 2);
      expect(
        repo.mediaCallCount,
        2,
        reason: 'the uploaded clip must be reused during reconciliation',
      );
    },
  );
}
