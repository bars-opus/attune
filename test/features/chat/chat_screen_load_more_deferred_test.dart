import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// The message list pages older history from its scroll notifications. A
/// scroll notification can arrive while the framework is building (a
/// ballistic restart or position hand-over inside a frame); calling
/// loadMoreMessages synchronously there writes the controller's state
/// mid-build and Riverpod asserts "Tried to modify a provider while the
/// widget tree was building." The list defers the call out of the frame,
/// once per burst of notifications.
void main() {
  testWidgets(
    'a near-the-top scroll notification dispatched while the tree builds '
    'loads older history after the build, once, without the Riverpod assert',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final base = DateTime.now().subtract(const Duration(days: 1));
      for (var i = 0; i < 120; i++) {
        repo.seedIncoming(
          id: 'm$i',
          relationshipId: 'rel-1',
          senderId: 'partner',
          content: 'message $i',
          createdAt: base.add(Duration(minutes: i)),
        );
      }
      final container = buildChatContainer(
        repository: repo,
        userId: 'user-a',
        extraOverrides: [
          chatConfigProvider.overrideWithValue(
            const ChatConfig(messagePageSize: 30),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 10));
        container.dispose();
      });
      final convo = activeConversation('rel-1');
      repo.conversationOverride = convo;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: withScreenUtil(
            MaterialApp(home: ChatScreen(conversation: convo)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      final state = container.read(chatControllerProvider(convo));
      expect(state.hasMore, isTrue);
      expect(state.isLoadingMore, isFalse);
      expect(state.messages.length, 30);
      final callsBefore = repo.getMessagesCalls;

      // A row of the list: the notification bubbles from it to the list's
      // NotificationListener, like one dispatched while the sliver builds
      // its rows.
      final row = tester.element(find.byType(MessageBubble).first);
      final position =
          tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byType(ListView),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
      final atTop = FixedScrollMetrics(
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
        pixels: position.maxScrollExtent,
        viewportDimension: position.viewportDimension,
        axisDirection: position.axisDirection,
        devicePixelRatio: 1.0,
      );

      Object? thrown;
      try {
        tester.binding.buildOwner!.buildScope(row, () {
          // A burst: start + end in the same build. (Only the paging
          // trigger reads these two; the pill and date chip react to
          // update/depth-0 notifications, which have their own guards.)
          ScrollStartNotification(metrics: atTop, context: row).dispatch(row);
          ScrollEndNotification(metrics: atTop, context: row).dispatch(row);
        });
      } catch (error) {
        thrown = error;
      }
      expect(
        thrown,
        isNull,
        reason: 'loadMoreMessages must not write state during a build',
      );

      // After the build it runs: once, not once per notification.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.getMessagesCalls - callsBefore, 1);
      expect(container.read(chatControllerProvider(convo)).messages.length, 60);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    },
  );
}
