import 'package:attune/app/routing/app_router.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/chat/presentation/widgets/video_message_player.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
import 'package:attune/features/chat/presentation/widgets/video_message_thumbnail.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/chat_test_harness.dart';

void main() {
  testWidgets('renders tombstone text when message is deleted', (tester) async {
    final deleted = Message.fromRow({
      'id': 'm1',
      'client_message_id': 'c1',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': null,
      'created_at': DateTime.now().toIso8601String(),
      'deleted_at': DateTime.now().toIso8601String(),
    }, currentUserId: 'u1');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MessageBubble(message: deleted))),
    );

    expect(find.text('This message was deleted'), findsOneWidget);
  });

  testWidgets('shows a star adornment when the message is starred', (
    tester,
  ) async {
    final message = Message.fromRow({
      'id': 'm-star',
      'client_message_id': 'c-star',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': 'hello',
      'created_at': DateTime.now().toIso8601String(),
    }, currentUserId: 'u1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message, isStarred: true)),
      ),
    );

    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });

  testWidgets('does not show a star icon when the message is not starred', (
    tester,
  ) async {
    final message = Message.fromRow({
      'id': 'm-unstarred',
      'client_message_id': 'c-unstarred',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': 'hello',
      'created_at': DateTime.now().toIso8601String(),
    }, currentUserId: 'u1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message, isStarred: false)),
      ),
    );

    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('does not render edited as a default footer label', (
    tester,
  ) async {
    final edited = Message.fromRow({
      'id': 'm2',
      'client_message_id': 'c2',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': 'updated text',
      'created_at': DateTime.now().toIso8601String(),
      'edited_at': DateTime.now().toIso8601String(),
    }, currentUserId: 'u1');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MessageBubble(message: edited))),
    );

    expect(find.textContaining('edited'), findsNothing);
  });

  testWidgets('edited messages do not expose a default footer tap target', (
    tester,
  ) async {
    Message? tapped;
    final edited = Message.fromRow({
      'id': 'm2b',
      'client_message_id': 'c2b',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': 'updated text',
      'created_at': DateTime.now().toIso8601String(),
      'edited_at': DateTime.now().toIso8601String(),
    }, currentUserId: 'u1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: edited,
            onShowEditHistory: (message) => tapped = message,
          ),
        ),
      ),
    );

    expect(find.text('edited'), findsNothing);
    expect(tapped, isNull);
  });

  testWidgets('long-press opens the actions sheet for a non-deleted message', (
    tester,
  ) async {
    final message = Message.optimistic(
      id: 'm3',
      clientMessageId: 'c3',
      relationshipId: 'r1',
      senderId: 'u1',
      content: 'hi',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            currentUserId: 'u1',
            onDelete: () {},
          ),
        ),
      ),
    );

    // textContaining, not text: message content now renders via Text.rich
    // with a trailing WidgetSpan (the inline time/status meta), so the
    // plain-text comparison find.text() does includes trailing
    // placeholder characters for those spans and would never equal 'hi'
    // exactly.
    await tester.longPress(find.textContaining('hi'));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets(
    'tapping the "+" opens the full emoji picker on a populated category, no exception',
    (tester) async {
      // Regression guard, two bugs found on real devices (neither reachable
      // via this widget-test harness on its own, so both are guarded here as
      // precisely as flutter test allows):
      // (1) emoji_picker_flutter's checkPlatformCompatibility (default true)
      //     force-unwraps a platform-channel call with no null check, which
      //     crashed on a real Android device with no native handler
      //     registered. checkPlatformCompatibility is now false. This path is
      //     gated behind Platform.isAndroid inside the package itself, so it
      //     never runs under flutter test's VM target — not exercised here,
      //     just guarded by keeping the config flag in place.
      // (2) The package's default initCategory is Category.RECENT, which is
      //     EMPTY on first use (nothing has ever been picked before) —
      //     confirmed on a real iOS Simulator: the sheet opened with no
      //     crash but showed no emoji at all. THIS bug IS reachable here:
      //     asserting EmojiCell actually renders is what would have caught
      //     it — the pre-fix version opens the sheet and finds zero cells.
      //
      // emoji_picker_flutter reads SharedPreferences on init regardless of
      // initCategory (recentTabBehavior still defaults to reading recents),
      // so this needs the same mock every other SharedPreferences-touching
      // test file in this suite uses.
      SharedPreferences.setMockInitialValues({});

      final message = Message.optimistic(
        id: 'm-emoji',
        clientMessageId: 'c-emoji',
        relationshipId: 'r1',
        senderId: 'u1',
        content: 'hi',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              currentUserId: 'u1',
              onReact: (_) {},
            ),
          ),
        ),
      );

      await tester.longPress(find.textContaining('hi'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(EmojiPicker), findsOneWidget);
      // The real content check: at least one emoji is actually rendered,
      // proving the sheet did not land on the empty first-use Recent tab.
      expect(find.byType(EmojiCell), findsWidgets);
    },
  );

  testWidgets(
    'the "+" still opens the picker when the list recycles the bubble while the menu is open',
    (tester) async {
      // THE regression guard for "tapping + does nothing", which the test above
      // could never catch: it renders a bare MessageBubble whose element is
      // never recycled, so the captured context stays mounted and the bug is
      // invisible.
      //
      // In production MessageBubble is built lazily inside ChatScreen's
      // ListView.builder. Its element is therefore recyclable, and the focused
      // menu route covers the list while it is open — so a list rebuild
      // underneath (realtime merge, reaction patch, scrolling past the cache
      // extent) can deactivate the bubble's element before "+" is tapped.
      // _openFullEmojiPicker used to receive that element's context and bail on
      // `!context.mounted`, silently doing nothing with no exception raised.
      // Capturing the NavigatorState at long-press time fixes it; against the
      // old context-based version this test fails with zero EmojiPicker found.
      SharedPreferences.setMockInitialValues({});

      var itemCount = 3;
      late StateSetter setOuter;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return ListView.builder(
                  itemCount: itemCount,
                  itemBuilder:
                      (context, index) => MessageBubble(
                        message: Message.optimistic(
                          id: 'm$index',
                          clientMessageId: 'c$index',
                          relationshipId: 'r1',
                          senderId: 'u1',
                          content: 'msg $index',
                          createdAt: DateTime.now(),
                        ),
                        currentUserId: 'u1',
                        onReact: (_) {},
                      ),
                );
              },
            ),
          ),
        ),
      );

      await tester.longPress(find.textContaining('msg 0'));
      await tester.pumpAndSettle();

      // The list rebuilds without the long-pressed message, unmounting that
      // bubble's element while the focused menu route is still up.
      setOuter(() => itemCount = 0);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(EmojiPicker), findsOneWidget);
      expect(find.byType(EmojiCell), findsWidgets);
    },
  );

  testWidgets(
    'long-press does nothing for a deleted message (no menu, nothing to act on)',
    (tester) async {
      final deleted = Message.fromRow({
        'id': 'm4',
        'client_message_id': 'c4',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': null,
        'created_at': DateTime.now().toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
      }, currentUserId: 'u1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: deleted,
              currentUserId: 'u1',
              onDelete: () {},
            ),
          ),
        ),
      );

      await tester.longPress(find.text('This message was deleted'));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsNothing);
    },
  );

  testWidgets(
    'long-press renders the bubble snapshot at the real bubble\'s size, no overflow',
    (tester) async {
      final message = Message.optimistic(
        id: 'm5',
        clientMessageId: 'c5',
        relationshipId: 'r1',
        senderId: 'u1',
        content: 'hi',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              currentUserId: 'u1',
              onDelete: () {},
            ),
          ),
        ),
      );

      // Size of the real bubble's text before the overlay opens.
      // textContaining, not text: message content renders via Text.rich
      // with a trailing WidgetSpan (the inline time/status meta), so
      // find.text()'s exact plain-text comparison would never match 'hi'.
      final realSize = tester.getSize(find.textContaining('hi'));

      await tester.longPress(find.textContaining('hi'));
      await tester.pumpAndSettle();

      // No layout overflow from the snapshot being re-rendered under the
      // dialog route (regression: without a Material ancestor the snapshot's
      // text fell back to Flutter's 48px debug style and overflowed).
      expect(tester.takeException(), isNull);

      // Two 'hi' Texts now exist: the real bubble and the overlay snapshot.
      // The snapshot must lay out at exactly the real bubble's size.
      final hiTexts = find.textContaining('hi');
      expect(hiTexts, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(tester.getSize(hiTexts.at(i)), realSize);
      }
    },
  );

  // NOTE: the "pop via the tile's own live context, not MessageBubble's"
  // behavior in buildMessageActionItems is covered by
  // test/features/chat/chat_screen_message_actions_test.dart, which drives
  // the real ChatScreen/ListView where the bubble's element actually does
  // get deactivated while the menu is open (6 of its tests fail if that
  // fix is reverted). A synthetic single-bubble rebuild here does not
  // reproduce the deactivation, so no local test is added for it.

  testWidgets(
    'shows a reaction pill with the emoji and count when the message has reactions',
    (tester) async {
      final message = Message.fromRow({
        'id': 'm-react',
        'client_message_id': 'c-react',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      }, currentUserId: 'u1').copyWith(
        reactions: {
          '❤️': {'u1', 'u2'},
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message, currentUserId: 'u1'),
          ),
        ),
      );

      expect(find.text('❤️'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets(
    'shows one pill per distinct emoji, no count badge when only one reactor',
    (tester) async {
      final message = Message.fromRow({
        'id': 'm-react2',
        'client_message_id': 'c-react2',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      }, currentUserId: 'u1').copyWith(
        reactions: {
          '❤️': {'u1'},
          '👍': {'u2'},
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message, currentUserId: 'u1'),
          ),
        ),
      );

      expect(find.text('❤️'), findsOneWidget);
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    },
  );

  testWidgets('tapping your own reaction pill removes the reaction', (
    tester,
  ) async {
    var removed = false;
    final message = Message.fromRow({
      'id': 'm-react-remove',
      'client_message_id': 'c-react-remove',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': 'hello',
      'created_at': DateTime.now().toIso8601String(),
    }, currentUserId: 'u1').copyWith(
      reactions: {
        '❤️': {'u1'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            currentUserId: 'u1',
            onRemoveReaction: () => removed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('❤️'));

    expect(removed, isTrue);
  });

  testWidgets(
    'playing your own voice message survives the optimistic-to-canonical id '
    'swap instead of self-pausing (I3 regression guard)',
    (tester) async {
      // The optimistic (pre-upload) message has a synthetic id like
      // '_local_<clientMessageId>'. Once the server confirms the send,
      // ChatController swaps it for the canonical row, which has a real UUID
      // as `id` but the SAME clientMessageId throughout.
      //
      // VoiceMessagePlayer enforces one-at-a-time playback by writing its own
      // `messageId` into currentlyPlayingVoiceMessageIdProvider on play, and
      // pausing itself via a ref.listen whenever the provider's value stops
      // matching `widget.messageId`. If MessageBubble sourced that messageId
      // from the unstable `message.id` instead of the stable
      // `clientMessageId`, then on the optimistic-to-canonical rebuild:
      // `widget.messageId` changes to the new id, but the provider still
      // holds the OLD id (nothing re-triggered play) — so the very next
      // ref.listen invocation sees `next != widget.messageId` and pauses
      // itself, even though no other bubble ever started playing. This test
      // starts playback under the optimistic identity, performs the swap,
      // and asserts the provider is untouched and the player has not
      // self-paused.
      const clientMessageId = 'c-voice-1';
      final createdAt = DateTime.now();

      final optimistic = Message.optimistic(
        id: '_local_$clientMessageId',
        clientMessageId: clientMessageId,
        relationshipId: 'r1',
        senderId: 'u1',
        content: '',
        createdAt: createdAt,
        mediaType: 'audio',
        localMediaPath: '/tmp/voice.m4a',
        mediaDurationMs: 4200,
        waveform: List.filled(100, 50),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: MessageBubble(message: optimistic)),
          ),
        ),
      );

      // Start playback — this synchronously writes widget.messageId into the
      // provider inside _togglePlayback, before the (never-resolving in this
      // test VM host) `await _player.play(source)`.
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      final messageIdWhilePlaying = container.read(
        currentlyPlayingVoiceMessageIdProvider,
      );
      expect(messageIdWhilePlaying, isNotNull);

      // Canonical row lands: different `id` (real UUID), same
      // clientMessageId, media now served from signedMediaUrl instead of
      // localMediaPath (post-upload) — the shape of the real swap.
      final canonical = optimistic.copyWith(
        id: 'server-generated-uuid',
        signedMediaUrl: 'https://example.com/voice.m4a',
        status: MessageStatus.sent,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: MessageBubble(message: canonical)),
          ),
        ),
      );
      await tester.pump();

      // A second, unrelated bubble starts playing — this is the real-world
      // trigger for the one-at-a-time enforcement's ref.listen to fire on
      // THIS (post-swap) bubble.
      final other = Message.optimistic(
        id: 'm-other',
        clientMessageId: 'c-other',
        relationshipId: 'r1',
        senderId: 'u1',
        content: '',
        createdAt: DateTime.now(),
        mediaType: 'audio',
        localMediaPath: '/tmp/other.m4a',
        mediaDurationMs: 1000,
        waveform: List.filled(100, 50),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  MessageBubble(message: canonical),
                  MessageBubble(message: other),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The provider is still exactly the value this bubble itself wrote
      // when play started (messageIdWhilePlaying) — the second bubble hasn't
      // been tapped, so nothing should have changed it yet. This establishes
      // the baseline before the real assertion below.
      expect(
        container.read(currentlyPlayingVoiceMessageIdProvider),
        messageIdWhilePlaying,
      );

      // Tapping play on THIS (post-swap) bubble again is the direct
      // observable check: _togglePlayback writes `widget.messageId` (the
      // CURRENT widget's messageId) into the provider. If MessageBubble
      // sourced it from the unstable message.id, this write now uses the
      // canonical id — a DIFFERENT value than messageIdWhilePlaying (the
      // optimistic id used for the original write) — even though, from the
      // user's perspective, it's the exact same voice message bubble they
      // were already listening to. The fix (clientMessageId) makes this
      // write produce the SAME value both times, proving stable identity
      // across the swap.
      final firstBubblePlayButtons = find.descendant(
        of: find.byType(MessageBubble).first,
        matching: find.byIcon(Icons.play_arrow_rounded),
      );
      // _isPlaying never actually flips true in this harness (play() never
      // resolves), so the icon is still play_arrow — tapping it re-enters
      // the "start playback" branch of _togglePlayback, which is exactly
      // the write we want to observe.
      await tester.tap(firstBubblePlayButtons);
      await tester.pump();

      expect(
        container.read(currentlyPlayingVoiceMessageIdProvider),
        messageIdWhilePlaying,
        reason:
            'the messageId this bubble writes into the provider must stay '
            'stable across the optimistic-to-canonical swap — if this fails, '
            'VoiceMessagePlayer is being identified by the unstable '
            'message.id instead of the stable message.clientMessageId',
      );
    },
  );

  testWidgets('no reaction pill renders when the message has no reactions', (
    tester,
  ) async {
    final message = Message.fromRow({
      'id': 'm-noreact',
      'client_message_id': 'c-noreact',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': 'hello',
      'created_at': DateTime.now().toIso8601String(),
    }, currentUserId: 'u1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: message, currentUserId: 'u1'),
        ),
      ),
    );

    expect(find.textContaining('❤'), findsNothing);
  });

  Conversation testConversation() => Conversation(
    id: 'r1',
    relationshipId: 'r1',
    partnerId: 'partner',
    name: 'Partner',
    updatedAt: DateTime(2026, 8, 16),
    relationshipStatus: 'active',
    availability: ConversationAvailability.active,
  );

  testWidgets(
    'an isViewOnce unviewed video renders the sealed tile, not VideoMessagePlayer',
    (tester) async {
      final message = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 'other',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: false,
        mediaType: 'video',
        isViewOnce: true,
        signedMediaUrl: 'https://example.com/clip.mp4',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              conversation: testConversation(),
            ),
          ),
        ),
      );

      expect(find.byType(VideoMessagePlayer), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'tapping an unviewed ephemeral video sealed tile pushes EphemeralVideoViewerScreen',
    (tester) async {
      final message = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 'other',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: false,
        mediaType: 'video',
        isViewOnce: true,
        signedMediaUrl: 'https://example.com/clip.mp4',
      );

      // EphemeralVideoViewerScreen reads chatRepositoryProvider (to call
      // markVideoViewed), which in turn needs supabaseClientProvider — a
      // real Supabase.instance is not initialized in this test host. Use
      // the shared chat_test_harness fake repository/container (the same
      // one ephemeral_video_viewer_screen_test.dart itself uses) rather
      // than a bare ProviderScope, so pushing the real screen doesn't hit
      // an uninitialized-Supabase assertion.
      final repo = FakeChatRepository(currentUserId: 'other');
      final container = buildChatContainer(repository: repo, userId: 'other');
      addTearDown(container.dispose);

      // Tapping the sealed tile now navigates via context.pushNamed
      // ('ephemeralVideoViewer', see app_router.dart), which requires a real
      // GoRouter ancestor — a bare MaterialApp/Navigator no longer suffices.
      final conversation = testConversation();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder:
                (context, state) => Scaffold(
                  body: MessageBubble(
                    message: message,
                    conversation: conversation,
                  ),
                ),
          ),
          GoRoute(
            path: '/viewer',
            name: 'ephemeralVideoViewer',
            builder: (context, state) {
              final args = state.extra as EphemeralVideoViewerRouteArgs;
              return EphemeralVideoViewerScreen(
                messageId: args.messageId,
                videoUrl: args.videoUrl,
                conversation: args.conversation,
              );
            },
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      // Two pumps to complete the route push: the first starts the ~300ms
      // transition, the second lets it finish (matches
      // ephemeral_video_viewer_screen_test.dart's own established pattern
      // for pushing this same screen).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(EphemeralVideoViewerScreen), findsOneWidget);
    },
  );

  testWidgets(
    'an ephemeral video still sending (synthetic id, local path only) is not tappable',
    (tester) async {
      // Mirrors the optimistic-message shape used elsewhere in this file
      // (see the I3 regression guard test above): a still-uploading
      // ephemeral video has a synthetic '_local_<clientMessageId>' id, only
      // a localMediaPath (no signedMediaUrl yet), and status ==
      // MessageStatus.sending. isEphemeralVideoAvailable is still true (it
      // only requires isViewOnce && viewedAt == null && a media path/url),
      // so without gating the tap on message.status, tapping this tile
      // would push EphemeralVideoViewerScreen with a synthetic id that
      // markVideoViewed can't match server-side — a confusing no-op open.
      final message = Message(
        id: '_local_c1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 'me',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
        localMediaPath: '/tmp/clip.mp4',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                conversation: testConversation(),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(find.byType(EphemeralVideoViewerScreen), findsNothing);
    },
  );

  testWidgets(
    'an isViewOnce viewed video renders the "Video expired" tombstone',
    (tester) async {
      final message = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 'other',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: false,
        mediaType: 'video',
        isViewOnce: true,
        viewedAt: DateTime(2026, 8, 16, 12),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              conversation: testConversation(),
            ),
          ),
        ),
      );

      expect(find.text('Video expired'), findsOneWidget);
      // No interactivity: behavioral check rather than a structural
      // GestureDetector search — UniversalBubble itself always wraps its
      // content in a long-press/swipe GestureDetector regardless of message
      // type, so a structural "no GestureDetector inside MessageBubble"
      // assertion would false-positive on that unrelated chrome. Tapping
      // directly on the tombstone's own text must not open the viewer (no
      // sealed-tile-style onTap wraps this branch's content specifically).
      await tester.tap(find.text('Video expired'), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(EphemeralVideoViewerScreen), findsNothing);
    },
  );

  testWidgets(
    'a non-view-once video message still renders its normal video tile',
    (tester) async {
      // Regression guard: an ordinary Part 1 gallery-pick video message
      // (isViewOnce == false, hasVideo == true) must render the ordinary
      // video tile — this is the test that would catch an accidental
      // branch-ordering regression sending an ordinary video down the
      // ephemeral/expired path.
      //
      // The tile is VideoMessageThumbnail (poster-only, tap opens the
      // full-screen viewer), not VideoMessagePlayer: the bubble no longer
      // plays inline. That split is what makes the tile's aspect ratio
      // stable — see VideoMessageThumbnail's class doc.
      final message = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 'other',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: false,
        mediaType: 'video',
        signedMediaUrl: 'https://example.com/clip.mp4',
        mediaDurationMs: 5000,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                conversation: testConversation(),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(VideoMessageThumbnail), findsOneWidget);
      expect(find.text('Video expired'), findsNothing);
    },
  );

  testWidgets(
    'a cold-open video row (no poster URL, only the cached thumbnail key) '
    'still resolves a poster instead of rendering a blank tile',
    (tester) async {
      // The cold-open shape, and the bug this guards: NONE of
      // localThumbnailPath / signedThumbnailUrl / signedMediaUrl are
      // persisted (client-only, or expiring signatures not worth caching),
      // so a row restored from the message cache carries only the storage
      // KEYS. The tile previously read `localThumbnailPath ??
      // signedThumbnailUrl`, got null for both, and painted a blank box
      // until hydration eventually re-signed a URL — which is why videos
      // showed as empty rectangles on app open while text was instant.
      final message = Message(
        id: 'm-cold',
        clientMessageId: 'c-cold',
        relationshipId: 'r1',
        senderId: 'other',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: false,
        mediaType: 'video',
        mediaKey: 'chat-media/r1/clip.mp4',
        mediaThumbnailKey: 'chat-media/r1/poster.jpg',
        mediaDurationMs: 5000,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                conversation: testConversation(),
              ),
            ),
          ),
        ),
      );

      // The tile renders immediately (never a blank/absent one) and a
      // resolver is in the tree working from the cached key.
      expect(find.byType(VideoMessageThumbnail), findsOneWidget);
      expect(find.byType(ResolvedMediaUrl), findsOneWidget);
      expect(find.text('Video expired'), findsNothing);
    },
  );
}
