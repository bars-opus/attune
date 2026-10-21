import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
// fake_async ships with flutter_test (same pattern as chat_controller_test).
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// All in fake time: "the open settled" and "the batch landed" are elapsed
/// fake durations, not real sleeps a loaded machine can outrun.
void main() {
  final t0 = DateTime.now().subtract(const Duration(minutes: 10));

  /// Long enough for the open, or one realtime batch, to land in fake time.
  const settle = Duration(seconds: 1);

  ({
    ProviderContainer container,
    ChatController controller,
    FakeHaptics haptics,
    FakeSoundService sound,
  })
  open(
    FakeAsync async,
    FakeChatRepository repo, {
    ChatCacheService? cache,
    bool inViewFromFirstFrame = false,
  }) {
    final haptics = FakeHaptics();
    final sound = FakeSoundService();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      cache: cache,
      extraOverrides: [
        hapticsProvider.overrideWithValue(haptics),
        soundServiceProvider.overrideWithValue(sound),
      ],
    );
    final controller = container.read(chatControllerProvider(convo).notifier);
    if (inViewFromFirstFrame) controller.setViewActive(true);
    async.elapse(settle);
    return (
      container: container,
      controller: controller,
      haptics: haptics,
      sound: sound,
    );
  }

  void close(FakeAsync async, ProviderContainer container) {
    container.dispose();
    async.flushMicrotasks();
  }

  void seedText(FakeChatRepository repo, String id, DateTime at) =>
      repo.seedIncoming(
        id: id,
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'text $id',
        createdAt: at,
      );

  void seedCard(
    FakeChatRepository repo,
    String id, {
    required String sender,
    required DateTime createdAt,
    DateTime? sortAt,
  }) => repo.seedIncoming(
    id: id,
    relationshipId: 'rel-1',
    senderId: sender,
    content: 'Snakes and Ladders',
    createdAt: createdAt,
    sortAt: sortAt,
    mediaType: 'game',
    gameSessionId: 's-$id',
  );

  test('a partner move while the chat is in view fires one light haptic '
      'and no receive chirp', () {
    fakeAsync((async) {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      // An older partner text, so the moved card is NOT the first-ever
      // partner row (that path has its own baseline semantics).
      seedText(repo, 'p0', t0.subtract(const Duration(hours: 1)));
      seedCard(repo, 'g1', sender: 'user-a', createdAt: t0);
      final rig = open(async, repo);
      rig.controller.setViewActive(true);

      // The partner plays: same id/created_at, new sender and sort_at.
      seedCard(
        repo,
        'g1',
        sender: 'partner',
        createdAt: t0,
        sortAt: DateTime.now(),
      );
      repo.emitRealtime();
      async.elapse(settle);

      expect(rig.haptics.lightCount, 1);
      expect(
        rig.haptics.selectionCount,
        0,
        reason: 'a move is not a new message (Review Focus 5)',
      );
      expect(rig.sound.played, isEmpty);
      close(async, rig.container);
    });
  });

  test('a partner move while backgrounded is silent', () {
    fakeAsync((async) {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedCard(repo, 'g1', sender: 'user-a', createdAt: t0);
      final rig = open(async, repo);
      rig.controller.setViewActive(false);

      seedCard(
        repo,
        'g1',
        sender: 'partner',
        createdAt: t0,
        sortAt: DateTime.now(),
      );
      repo.emitRealtime();
      async.elapse(settle);

      expect(rig.haptics.lightCount, 0);
      close(async, rig.container);
    });
  });

  test('my own move gives no haptic', () {
    fakeAsync((async) {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedCard(repo, 'g1', sender: 'partner', createdAt: t0);
      final rig = open(async, repo);
      rig.controller.setViewActive(true);

      seedCard(
        repo,
        'g1',
        sender: 'user-a',
        createdAt: t0,
        sortAt: DateTime.now(),
      );
      repo.emitRealtime();
      async.elapse(settle);

      expect(rig.haptics.lightCount, 0);
      close(async, rig.container);
    });
  });

  test('my own move leaves a partner-sided trail: no haptic, no chirp', () {
    // leave_game_trail copies the card's OLD sender and created_at. When I
    // take a card off the partner's side, the trail is a partner row whose
    // created_at can be newer than their last text — it used to read as a
    // "new partner message" and fire the receive feedback.
    fakeAsync((async) {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedText(repo, 'p0', t0.subtract(const Duration(hours: 1)));
      seedCard(repo, 'g1', sender: 'partner', createdAt: t0);
      final rig = open(async, repo);
      rig.controller.setViewActive(true);

      // I play: the trail keeps the partner's side and the card's old time;
      // the card comes to my side at the bottom.
      repo.seedIncoming(
        id: 't1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'Snakes and Ladders',
        createdAt: t0,
        mediaType: 'game_trail',
        gameSessionId: 's-g1',
      );
      seedCard(
        repo,
        'g1',
        sender: 'user-a',
        createdAt: t0,
        sortAt: DateTime.now(),
      );
      repo.emitRealtime();
      async.elapse(settle);

      expect(rig.haptics.lightCount, 0);
      expect(rig.haptics.selectionCount, 0);
      expect(rig.sound.played, isEmpty);
      close(async, rig.container);
    });
  });

  test('opening on a warm cache where the partner moved while I was away '
      'does not buzz', () {
    // The cache still has the card on my side at its old slot; the server
    // has it on the partner's side at the bottom. That difference is the
    // baseline fold at open, not a live move.
    fakeAsync((async) {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final cached = repo.seedIncoming(
        id: 'g1',
        relationshipId: 'rel-1',
        senderId: 'user-a',
        content: 'Snakes and Ladders',
        createdAt: t0,
        mediaType: 'game',
        gameSessionId: 's-g1',
      );
      cache.writeMessages('user-a', 'rel-1', [cached]);
      async.flushMicrotasks();
      seedCard(
        repo,
        'g1',
        sender: 'partner',
        createdAt: t0,
        sortAt: DateTime.now(),
      );
      // In view from the first frame, as on a push-open.
      final rig = open(async, repo, cache: cache, inViewFromFirstFrame: true);
      expect(
        rig.container
            .read(chatControllerProvider(activeConversation('rel-1')))
            .messages
            .singleWhere((m) => m.id == 'g1')
            .isMine,
        isFalse,
        reason: 'the server copy (partner side) must have landed',
      );

      expect(rig.haptics.lightCount, 0);
      expect(rig.haptics.selectionCount, 0);
      expect(rig.sound.played, isEmpty);
      close(async, rig.container);
    });
  });

  test('a realtime batch that lands mid-open (catch-up fails, a by-id '
      'refresh works) cannot turn the open into a move', () {
    // Review M-1: the warm cache holds the card at its old slot; a batch
    // processed while the first page is in flight records that cached slot
    // through the touched-rows refresh; then the first page brings the
    // card's server slot. Only the baseline guards keep that from buzzing.
    fakeAsync((async) {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final text = repo.seedIncoming(
        id: 'p0',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'your turn',
        createdAt: t0.subtract(const Duration(hours: 1)),
      );
      final cached = repo.seedIncoming(
        id: 'g1',
        relationshipId: 'rel-1',
        senderId: 'user-a',
        content: 'Snakes and Ladders',
        createdAt: t0,
        mediaType: 'game',
        gameSessionId: 's-g1',
      );
      cache.writeMessages('user-a', 'rel-1', [cached, text]);
      async.flushMicrotasks();
      // The server has the card on the partner's side, newer than the cache.
      seedCard(
        repo,
        'g1',
        sender: 'partner',
        createdAt: t0,
        sortAt: DateTime.now(),
      );
      final firstPage = repo.getMessagesGate = Completer<void>();
      repo.getMessagesAfterError = StateError('catch-up offline');

      final haptics = FakeHaptics();
      final sound = FakeSoundService();
      final convo = activeConversation('rel-1');
      repo.conversationOverride = convo;
      final container = buildChatContainer(
        repository: repo,
        userId: 'user-a',
        cache: cache,
        extraOverrides: [
          hapticsProvider.overrideWithValue(haptics),
          soundServiceProvider.overrideWithValue(sound),
        ],
      );
      final controller = container.read(chatControllerProvider(convo).notifier);
      controller.setViewActive(true);
      async.elapse(const Duration(milliseconds: 100));
      expect(
        container.read(chatControllerProvider(convo)).messages,
        isNotEmpty,
        reason: 'the warm cache is on screen while the first page waits',
      );

      // An update frame for the held text: catch-up throws, the by-id
      // refresh of p0 succeeds — and sees the CACHED card.
      repo.emitRealtime(
        const ChatRealtimeEvent(
          ChatRealtimeKind.messageUpdate,
          messageId: 'p0',
        ),
      );
      // Past the 250 ms realtime debounce.
      async.elapse(const Duration(milliseconds: 400));
      expect(
        repo.getMessagesByIdsCalls,
        greaterThan(0),
        reason: 'path reached',
      );
      repo.getMessagesAfterError = null;

      firstPage.complete();
      async.elapse(settle);
      expect(
        container
            .read(chatControllerProvider(convo))
            .messages
            .singleWhere((m) => m.id == 'g1')
            .isMine,
        isFalse,
        reason: 'the first page brought the server slot',
      );

      expect(haptics.lightCount, 0);
      expect(haptics.selectionCount, 0);
      close(async, container);
    });
  });

  group('a new game card is a new message (review I-1)', () {
    test('a partner invite while in view fires the receive feedback once; a '
        'later move on that card fires only the move tap', () {
      fakeAsync((async) {
        final repo = FakeChatRepository(currentUserId: 'user-a');
        seedText(repo, 'p0', t0.subtract(const Duration(hours: 1)));
        final rig = open(async, repo);
        rig.controller.setViewActive(true);

        // post_game_message: a NEW row, partner-sent, created now.
        final inviteAt = DateTime.now();
        seedCard(repo, 'g2', sender: 'partner', createdAt: inviteAt);
        repo.emitRealtime();
        async.elapse(settle);

        expect(rig.haptics.selectionCount, 1, reason: 'invite = message');
        expect(rig.sound.played, [ChatSound.receive]);
        expect(rig.haptics.lightCount, 0);

        // I accept and play: the card comes to my side. Not a partner
        // message, and the older partner text it uncovers is not new.
        seedCard(
          repo,
          'g2',
          sender: 'user-a',
          createdAt: inviteAt,
          sortAt: DateTime.now().add(const Duration(seconds: 1)),
        );
        repo.emitRealtime();
        async.elapse(settle);
        expect(rig.haptics.selectionCount, 1);
        expect(rig.haptics.lightCount, 0);

        // The partner plays back: a move, not a message.
        seedCard(
          repo,
          'g2',
          sender: 'partner',
          createdAt: inviteAt,
          sortAt: DateTime.now().add(const Duration(seconds: 2)),
        );
        repo.emitRealtime();
        async.elapse(settle);

        expect(rig.haptics.selectionCount, 1);
        expect(rig.haptics.lightCount, 1);
        expect(rig.sound.played, [ChatSound.receive]);
        close(async, rig.container);
      });
    });

    test('an invite first seen through a by-id refresh still fires the '
        'receive feedback (T7 carry)', () {
      // The invite's INSERT frame is lost and the catch-up fails; an
      // UPDATE frame for the new card arrives, so the by-id refresh is the
      // first to merge it. That path used to record the card as KNOWN
      // without asking whether it was new, and every later merge then
      // treated the invite as a move: silent.
      fakeAsync((async) {
        final repo = FakeChatRepository(currentUserId: 'user-a');
        seedText(repo, 'p0', t0.subtract(const Duration(hours: 1)));
        final rig = open(async, repo);
        rig.controller.setViewActive(true);

        seedCard(repo, 'g2', sender: 'partner', createdAt: DateTime.now());
        repo.getMessagesAfterError = StateError('catch-up offline');
        repo.emitRealtime(
          const ChatRealtimeEvent(
            ChatRealtimeKind.messageUpdate,
            messageId: 'g2',
          ),
        );
        async.elapse(const Duration(milliseconds: 400));
        expect(repo.getMessagesByIdsCalls, greaterThan(0), reason: 'path');
        repo.getMessagesAfterError = null;
        async.elapse(settle);

        expect(rig.haptics.selectionCount, 1, reason: 'invite = message');
        expect(rig.sound.played, [ChatSound.receive]);
        expect(rig.haptics.lightCount, 0);

        // A later merge does not fire it again.
        repo.emitRealtime();
        async.elapse(settle);
        expect(rig.haptics.selectionCount, 1);
        expect(rig.sound.played, [ChatSound.receive]);
        close(async, rig.container);
      });
    });

    test('my own invite fires nothing', () {
      fakeAsync((async) {
        final repo = FakeChatRepository(currentUserId: 'user-a');
        seedText(repo, 'p0', t0.subtract(const Duration(hours: 1)));
        final rig = open(async, repo);
        rig.controller.setViewActive(true);

        seedCard(repo, 'g2', sender: 'user-a', createdAt: DateTime.now());
        repo.emitRealtime();
        async.elapse(settle);

        expect(rig.haptics.selectionCount, 0);
        expect(rig.haptics.lightCount, 0);
        expect(rig.sound.played, isEmpty);
        close(async, rig.container);
      });
    });
  });

  test('an archive purge clears the receive/move ledger (T7 carry)', () {
    fakeAsync((async) {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedText(repo, 'p0', t0.subtract(const Duration(hours: 1)));
      seedCard(repo, 'g1', sender: 'user-a', createdAt: t0);
      final rig = open(async, repo);
      expect(rig.controller.debugReceiveLedgerIsEmpty, isFalse);

      repo.conversationOverride = activeConversation(
        'rel-1',
      ).copyWith(availability: ConversationAvailability.archived);
      repo.emitRealtime(
        const ChatRealtimeEvent(ChatRealtimeKind.relationship),
      );
      async.elapse(settle);
      expect(
        rig.container
            .read(chatControllerProvider(activeConversation('rel-1')))
            .messages,
        isEmpty,
        reason: 'purged',
      );
      expect(rig.controller.debugReceiveLedgerIsEmpty, isTrue);

      // Un-archived and resynced: whatever comes back is history, never
      // announced (the purge dropped the baseline with the ledger).
      rig.controller.setViewActive(true);
      repo.conversationOverride = activeConversation('rel-1');
      repo.emitRealtime(
        const ChatRealtimeEvent(ChatRealtimeKind.relationship),
      );
      async.elapse(settle);
      repo.emitRealtime(const ChatRealtimeEvent(ChatRealtimeKind.resync));
      async.elapse(settle);
      expect(
        rig.container
            .read(chatControllerProvider(activeConversation('rel-1')))
            .messages,
        isNotEmpty,
        reason: 'the rows came back',
      );
      expect(rig.haptics.selectionCount, 0);
      expect(rig.haptics.lightCount, 0);
      expect(rig.sound.played, isEmpty);
      close(async, rig.container);
    });
  });

  test('one merge with a partner move AND a new partner text gives one '
      'haptic: the message feedback wins (review M-2)', () {
    fakeAsync((async) {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedText(repo, 'p0', t0.subtract(const Duration(hours: 1)));
      seedCard(repo, 'g1', sender: 'user-a', createdAt: t0);
      final rig = open(async, repo);
      rig.controller.setViewActive(true);

      seedCard(
        repo,
        'g1',
        sender: 'partner',
        createdAt: t0,
        sortAt: DateTime.now(),
      );
      seedText(repo, 'p1', DateTime.now().add(const Duration(seconds: 1)));
      repo.emitRealtime();
      async.elapse(settle);

      expect(rig.haptics.selectionCount, 1);
      expect(rig.haptics.lightCount, 0, reason: 'no second buzz');
      expect(rig.sound.played, [ChatSound.receive]);
      close(async, rig.container);
    });
  });
}
