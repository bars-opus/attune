// The per-chat realtime channel's lifecycle in SupabaseChatRepository (no
// server: the client points at a closed port, so nothing ever joins).

import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/data/repositories/supabase_chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('only the channel\'s first subscribe is an initial resync (M2)', () {
    final first = chatResyncEventFor(
      RealtimeSubscribeStatus.subscribed,
      joinedBefore: false,
    );
    final again = chatResyncEventFor(
      RealtimeSubscribeStatus.subscribed,
      joinedBefore: true,
    );
    expect(first?.kind, ChatRealtimeKind.resync);
    expect(first?.initial, isTrue);
    expect(again?.kind, ChatRealtimeKind.resync);
    expect(again?.initial, isFalse, reason: 'a reconnect is a full resync');
    for (final status in [
      RealtimeSubscribeStatus.channelError,
      RealtimeSubscribeStatus.timedOut,
      RealtimeSubscribeStatus.closed,
    ]) {
      expect(chatResyncEventFor(status, joinedBefore: false), isNull);
    }
  });

  test('a chat re-subscribing while its old channel is still being released '
      'gets a live stream, not the one being closed (M6)', () async {
    final client = SupabaseClient('http://127.0.0.1:9', 'test-anon-key');
    addTearDown(client.dispose);
    final repository = SupabaseChatRepository(client);

    final old = repository.watchConversationEvents('rel-1').listen((_) {});
    // The controller being replaced releases its channel (unawaited, as in
    // ChatController.dispose) and the new controller subscribes at once.
    await old.cancel();
    final release = repository.releaseChannel('rel-1');
    var closed = false;
    final fresh = repository
        .watchConversationEvents('rel-1')
        .listen((_) {}, onDone: () => closed = true);
    addTearDown(fresh.cancel);
    await release;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(closed, isFalse);
  });
}
