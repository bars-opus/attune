import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  test('a sent message is written to the cache, not only to memory', () async {
    // _attemptSend updated state and cleared the outbox but never wrote the
    // message cache — that happens only in loadMessages/refreshMessages. So
    // a just-sent message lived in memory alone: leaving the screen dropped
    // it, the warm-cache restore on return did not have it, and it
    // reappeared seconds later when the server fetch landed.
    final repo = FakeChatRepository(currentUserId: 'me');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

    final container = buildChatContainer(repository: repo, userId: 'me');
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await controller.sendMessage('persist me');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final cache = container.read(chatCacheServiceProvider);
    final cached = await cache.readMessages('me', 'rel-1');

    expect(
      cached.where((m) => m.content == 'persist me'),
      isNotEmpty,
      reason:
          'the message must survive leaving the screen without waiting for '
          'a server round-trip',
    );
  });
}
