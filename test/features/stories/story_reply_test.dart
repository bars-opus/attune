// Tests for Task 6 (task-6-brief.md; spec §5.4): replies from the reel
// landing in chat.
//
// Binding authority is docs/superpowers/specs/2026-09-11-stories-design.md
// §5.4. Three of its rules shape this suite:
//
//   1. A reply is an ordinary `messages` INSERT with `story_item_id` set
//      (never a story-reply RPC) — this screen sends through
//      chatRepositoryProvider.sendTextMessage directly, not through the
//      story outbox (§6.1's outbox is for POSTING a story; a reply is
//      chat, per §5.4's own opening rationale).
//   2. The client must NEVER send its own quoted_text for a story reply —
//      the server trigger overwrites it regardless. Proven below by
//      asserting on the exact call FakeChatRepository received, not just
//      on what came back.
//   3. A reply's live link can go away (soft delete) while quoted_text
//      survives; tapping the quote must say "Story no longer available"
//      rather than open an empty reel — proven via a direct
//      StoryReadGateway.getReplyTarget stub, mirroring
//      story_items_read_members' own deleted_at IS NULL filter (a null
//      result IS the "unavailable" case, not a distinguishable error).
//
// VARYING dimensions deliberately (this plan's own lesson, task-6-brief.md
// preamble): photo vs video story, live vs deleted story, own vs partner's
// item — a fixture uniform in any of these would hide exactly the bug it
// exists to catch.
//
// NO REAL-CLOCK WAITS: every wait is `tester.pump()`/`pumpAndSettle()`
// inside the FakeAsync zone testWidgets already runs in.

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/support/chat_test_harness.dart';

const _myId = 'me-1';
const _partnerId = 'partner-1';
const _relationshipId = 'rel-1';

final _signedInUser = User(
  id: _myId,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

StoryItem _item({
  required String id,
  required DateTime createdAt,
  String mediaType = 'image',
  String authorId = _partnerId,
}) {
  return StoryItem(
    id: id,
    clientStoryId: 'client-$id',
    relationshipId: _relationshipId,
    authorId: authorId,
    mediaType: mediaType,
    mediaKey: 'story-media/$id.jpg',
    thumbnailKey: 'story-media/$id-thumb.jpg',
    mediaWidth: 1080,
    mediaHeight: 1920,
    durationMs: mediaType == 'video' ? 4000 : null,
    occurredOn: createdAt,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    hasBeenViewed: false,
  );
}

/// Minimal StoryReadGateway fake for this suite: one script of active
/// items, and a settable getReplyTarget answer for the message_bubble
/// tap-through tests below. Deliberately separate from story_reel_test
/// .dart's own _FakeReelGateway rather than importing a private class
/// from another test file.
class _FakeGateway implements StoryReadGateway {
  _FakeGateway({List<StoryItem> items = const []}) : _items = items;

  final List<StoryItem> _items;
  final List<String> markViewedCalls = [];
  StoryReplyTarget? replyTargetAnswer;
  int getReplyTargetCallCount = 0;

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) async => StoryItemPage(items: List.of(_items), nextCursor: null);

  @override
  Future<String?> signMediaUrl(String storageKey) async =>
      'https://signed.example/$storageKey';

  @override
  Future<void> markViewed({required String storyItemId}) async {
    markViewedCalls.add(storyItemId);
  }

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async => const [];

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) async => const [];

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) async => const StoryItemPage(items: [], nextCursor: null);

  @override
  Future<void> deleteItem({required String storyItemId}) async {}

  @override
  Future<StoryReplyTarget?> getReplyTarget({
    required String storyItemId,
  }) async {
    getReplyTargetCallCount++;
    return replyTargetAnswer;
  }

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      const Stream.empty();

  @override
  void disposeChannel(String relationshipId) {}

  @override
  void disposeAllChannels() {}
}

Widget _reelHarness({
  required StoryReadGateway gateway,
  required ChatRepository chatRepository,
  bool isOwnReel = false,
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(_signedInUser),
      storyReadGatewayProvider.overrideWithValue(gateway),
      chatRepositoryProvider.overrideWithValue(chatRepository),
    ],
    child: MaterialApp(
      home: StoryReelScreen(
        relationshipId: _relationshipId,
        authorId: _partnerId,
        isOwnReel: isOwnReel,
        // Skip the image hold entirely — these tests only need the
        // composer visible and functional, not the progress ticker.
        imageHoldDuration: const Duration(seconds: 30),
      ),
    ),
  );
}

Message _storyReplyMessage({
  String id = 'srv-1',
  String storyItemId = 'story-1',
  String quotedText = 'Photo story',
  String senderId = _myId,
}) {
  return Message(
    id: id,
    clientMessageId: 'client-$id',
    relationshipId: _relationshipId,
    senderId: senderId,
    content: 'love this',
    createdAt: DateTime(2026, 9, 12, 10, 0),
    status: MessageStatus.sent,
    isMine: senderId == _myId,
    quotedText: quotedText,
    storyItemId: storyItemId,
  );
}

Widget _bubbleHarness({
  required Message message,
  required StoryReadGateway gateway,
}) {
  return ProviderScope(
    overrides: [storyReadGatewayProvider.overrideWithValue(gateway)],
    child: MaterialApp(
      home: Scaffold(body: MessageBubble(message: message)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('replying from the reel composes a message quoting the story', () {
    testWidgets(
      'typing a reply and sending it calls sendTextMessage with '
      'storyItemId set to the CURRENT item and no quotedText of its own',
      (tester) async {
        final items = [
          _item(id: 'story-photo', createdAt: DateTime.utc(2026, 9, 1)),
        ];
        final gateway = _FakeGateway(items: items);
        final chatRepo = FakeChatRepository(currentUserId: _myId);

        await tester.pumpWidget(
          _reelHarness(gateway: gateway, chatRepository: chatRepo),
        );
        await tester.pump();
        await tester.pump();

        await tester.enterText(
          find.byKey(const ValueKey('story-reel-reply-field')),
          'so pretty!',
        );
        await tester.tap(find.byKey(const ValueKey('story-reel-reply-send')));
        await tester.pump();
        await tester.pump();

        expect(chatRepo.sendCallCount, 1);
        final call = chatRepo.lastSendArgs!;
        expect(call.storyItemId, 'story-photo');
        expect(call.content, 'so pretty!');
        expect(call.relationshipId, _relationshipId);
        // Rule 2 (this file's header): the client must never send its
        // own quotedText for a story reply.
        expect(call.quotedText, isNull);
      },
    );

    testWidgets(
      'sending a reply to a VIDEO item still sets storyItemId, not '
      'quotedText — the media-type branch is not special-cased away',
      (tester) async {
        final items = [
          _item(
            id: 'story-video',
            createdAt: DateTime.utc(2026, 9, 1),
            mediaType: 'video',
          ),
        ];
        final gateway = _FakeGateway(items: items);
        final chatRepo = FakeChatRepository(currentUserId: _myId);

        await tester.pumpWidget(
          _reelHarness(gateway: gateway, chatRepository: chatRepo),
        );
        await tester.pump();
        await tester.pump();

        await tester.enterText(
          find.byKey(const ValueKey('story-reel-reply-field')),
          'nice clip',
        );
        await tester.tap(find.byKey(const ValueKey('story-reel-reply-send')));
        await tester.pump();
        await tester.pump();

        expect(chatRepo.sendCallCount, 1);
        expect(chatRepo.lastSendArgs!.storyItemId, 'story-video');
        expect(chatRepo.lastSendArgs!.quotedText, isNull);
      },
    );

    testWidgets(
      'the reply composer does not render at all on your OWN story',
      (tester) async {
        final items = [
          _item(
            id: 'mine',
            createdAt: DateTime.utc(2026, 9, 1),
            authorId: _myId,
          ),
        ];
        final gateway = _FakeGateway(items: items);
        final chatRepo = FakeChatRepository(currentUserId: _myId);

        await tester.pumpWidget(
          _reelHarness(
            gateway: gateway,
            chatRepository: chatRepo,
            isOwnReel: true,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('story-reel-reply-field')),
          findsNothing,
        );
      },
    );
  });

  group('a reply to a DELETED story still reads sensibly', () {
    testWidgets(
      'quoted_text renders in the bubble even when the live story is gone',
      (tester) async {
        final message = _storyReplyMessage(quotedText: 'Photo story');
        final gateway = _FakeGateway()..replyTargetAnswer = null;

        await tester.pumpWidget(
          _bubbleHarness(message: message, gateway: gateway),
        );
        await tester.pump();

        // The durable snapshot survives regardless of live availability
        // (spec §5.4: quoted_text is never cleared by the story's own
        // deletion) — rendered unconditionally, before any tap.
        expect(find.text('Photo story'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping the quote of a story that getReplyTarget resolves to null '
      '(soft-deleted, or otherwise no longer available) shows '
      '"Story no longer available" and does NOT open the reel',
      (tester) async {
        final message = _storyReplyMessage(quotedText: 'Video story');
        final gateway = _FakeGateway()..replyTargetAnswer = null;

        await tester.pumpWidget(
          _bubbleHarness(message: message, gateway: gateway),
        );
        await tester.pump();

        await tester.tap(find.text('Video story'));
        await tester.pump();
        await tester.pump();

        expect(gateway.getReplyTargetCallCount, 1);
        expect(find.text('Story no longer available'), findsOneWidget);
        // Never navigated anywhere — the reel screen must not appear.
        expect(find.byType(StoryReelScreen), findsNothing);
      },
    );

    testWidgets(
      'tapping the quote of a story that IS still available opens the reel '
      'at its day, and shows no "unavailable" message',
      (tester) async {
        final message = _storyReplyMessage(
          storyItemId: 'story-live',
          quotedText: 'Photo story',
        );
        final gateway = _FakeGateway()
          ..replyTargetAnswer = StoryReplyTarget(
            relationshipId: _relationshipId,
            authorId: _partnerId,
            occurredOn: DateTime.utc(2026, 9, 5),
          );

        await tester.pumpWidget(
          _bubbleHarness(message: message, gateway: gateway),
        );
        await tester.pump();

        await tester.tap(find.text('Photo story'));
        await tester.pump();
        await tester.pump();

        expect(gateway.getReplyTargetCallCount, 1);
        expect(find.byType(StoryReelScreen), findsOneWidget);
        expect(find.text('Story no longer available'), findsNothing);
      },
    );
  });
}
