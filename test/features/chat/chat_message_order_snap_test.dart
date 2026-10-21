import 'dart:async';

import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// 1a final ruling 2, carried into Task 9 (Step 2b): an acknowledged own
/// bubble keeps its device-time slot (no jump on send), but the next GENUINE
/// arrival lets server order win. Before, the slot was carried for the whole
/// session, so a phone whose clock ran ahead kept its own bubble below a
/// partner reply that was actually sent after it.
///
/// The fake stamps a send `now + sendCreatedAtOffset` on the server, so an
/// offset of -5 min is a device clock running 5 min ahead: the optimistic
/// row says `now`, the server says `now - 5m`.
void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  Future<
    ({
      FakeChatRepository repo,
      ChatController controller,
      List<String> Function() order,
    })
  >
  boot({List<({String id, Duration ago})> held = const []}) async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..sendCreatedAtOffset = const Duration(minutes: -5);
    for (final row in held) {
      repo.seedIncoming(
        id: row.id,
        relationshipId: relId,
        senderId: 'partner',
        content: row.id,
        createdAt: DateTime.now().subtract(row.ago),
      );
    }
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    List<String> order() =>
        container
            .read(chatControllerProvider(convo))
            .messages
            .map((m) => m.content)
            .toList();
    return (repo: repo, controller: controller, order: order);
  }

  Future<void> realtime(FakeChatRepository repo) async {
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  test('a partner reply sent after mine is newer than mine (newest-first '
      '[reply, mine]) even when my clock runs ahead', () async {
    final s = await boot();
    await s.controller.sendMessage('mine');
    // Acked: the bubble keeps its device-time slot.
    expect(s.order(), ['mine']);

    // Server time: mine at now-5m, the reply at now-4m (after mine), which
    // is still BEFORE my device's `now`.
    s.repo.seedIncoming(
      id: 'reply',
      relationshipId: relId,
      senderId: 'partner',
      content: 'reply',
      createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
    );
    await realtime(s.repo);

    expect(s.order(), ['reply', 'mine']);
  });

  test('my own ack alone does not reorder (no jump on send)', () async {
    // Held before I send; server-newer than my ack (now-5m), device-older
    // than my optimistic `now`.
    final s = await boot(held: [(id: 'held', ago: const Duration(minutes: 2))]);
    await s.controller.sendMessage('mine');
    expect(s.order(), ['mine', 'held']);

    await realtime(s.repo);
    expect(s.order(), ['mine', 'held']);

    // A second own send is not an arrival either.
    await s.controller.sendMessage('mine 2');
    await realtime(s.repo);
    expect(s.order(), ['mine 2', 'mine', 'held']);
  });

  test('my own row reaching a realtime merge before its ack is not an '
      'arrival', () async {
    // 'older' keeps my server times (≈ now-5m) inside the held span, so only
    // the clientMessageId match keeps my own row from counting.
    final s = await boot(
      held: [
        (id: 'held', ago: const Duration(minutes: 2)),
        (id: 'older', ago: const Duration(minutes: 10)),
      ],
    );
    await s.controller.sendMessage('mine 1');
    expect(s.order(), ['mine 1', 'held', 'older']);

    // The server commits 'mine 2'; its answer is held back, so the next
    // realtime merge sees that canonical row while the optimistic one is
    // still in the list. Counted as an arrival, it would snap 'mine 1'
    // (server now-5m) below 'held' (now-2m).
    final answer = Completer<void>();
    s.repo.sendResponseGates.add(answer);
    final sending = s.controller.sendMessage('mine 2');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await realtime(s.repo);
    expect(s.order(), ['mine 2', 'mine 1', 'held', 'older']);

    answer.complete();
    await sending;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(s.order(), ['mine 2', 'mine 1', 'held', 'older']);
  });

  test('an edit or a reaction on a held row does not snap the order', () async {
    final s = await boot(held: [(id: 'held', ago: const Duration(minutes: 2))]);
    await s.controller.sendMessage('mine');
    expect(s.order(), ['mine', 'held']);

    final held = s.repo.serverMessages['held']!;
    s.repo.serverMessages['held'] = held.copyWith(editedAt: DateTime.now());
    s.repo.touch('held');
    await realtime(s.repo);
    expect(s.order(), ['mine', 'held']);

    await s.repo.addReaction(
      relationshipId: relId,
      messageId: 'held',
      emoji: '❤️',
    );
    await realtime(s.repo);
    expect(s.order(), ['mine', 'held']);
  });

  test('an older history page is not an arrival', () async {
    // 61 held rows: the first page (50) is the newest, 11 wait older.
    final s = await boot(
      held: [
        (id: 'held', ago: const Duration(minutes: 2)),
        for (var i = 0; i < 60; i++)
          (id: 'old $i', ago: Duration(minutes: 60 + i)),
      ],
    );
    await s.controller.sendMessage('mine');
    expect(s.order().take(2), ['mine', 'held']);
    final before = s.order().length;

    await s.controller.loadMoreMessages();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.order().length, greaterThan(before), reason: 'a page loaded');
    expect(s.order().take(2), ['mine', 'held']);
  });

  group('a brand-new chat with an unacked first send', () {
    // The only held row is optimistic, stamped with my device clock (5 min
    // ahead). The window floor must come from server-backed rows, or the
    // reply (server now-4m, after mine at now-5m) would look "older than
    // everything held" and not count as an arrival.
    Future<void> replyWhilePending(FakeChatRepository repo) async {
      repo.seedIncoming(
        id: 'reply',
        relationshipId: relId,
        senderId: 'partner',
        content: 'reply',
        createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
      );
      await realtime(repo);
    }

    test('committed but unanswered: the merge that brings the reply orders '
        'by server time', () async {
      final s = await boot();
      final answer = Completer<void>();
      s.repo.sendResponseGates.add(answer);
      final sending = s.controller.sendMessage('mine');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(s.order(), ['mine']);

      await replyWhilePending(s.repo);
      answer.complete();
      await sending;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(s.order(), ['reply', 'mine']);
    });

    test('not yet committed: the ack takes server order', () async {
      final s = await boot();
      s.repo.sendDelay = const Duration(seconds: 1);
      final sending = s.controller.sendMessage('mine');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await replyWhilePending(s.repo);
      // The reply sits above my pending bubble (its device stamp is newer).
      expect(s.order(), ['mine', 'reply']);

      await sending;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(s.order(), ['reply', 'mine']);
    });
  });
}
