import 'dart:async';

import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/widgets/game_message_bubble.dart';
import 'package:attune/features/games/presentation/widgets/game_trail_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// #43 (M-5): `move_game_card` keeps the card's id/client id/created_at and
/// rewrites only sender_id and sort_at, while `leave_game_trail` inserts a
/// NEW row at the card's old slot. The identity-based arrival tracker saw
/// the opposite of what happened: the card teleported to the bottom with no
/// motion, and the trail slid/faded in mid-history where nobody looked.
void main() {
  final base = DateTime.now().subtract(const Duration(hours: 1));

  /// [count] texts a minute apart, plus my game card after text [cardAfter].
  void seedHistory(
    FakeChatRepository repo, {
    int count = 40,
    int cardAfter = 10,
  }) {
    for (var i = 0; i < count; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: i.isEven ? 'partner' : 'user-a',
        content: 'message $i',
        createdAt: base.add(Duration(minutes: i)),
      );
    }
    repo.seedIncoming(
      id: 'g1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'Snakes and Ladders',
      createdAt: base.add(Duration(minutes: cardAfter, seconds: 30)),
      mediaType: 'game',
      gameSessionId: 's1',
    );
  }

  /// The partner plays: the trail keeps my side and the card's old slot;
  /// the card comes to the partner's side at the bottom.
  void partnerMoves(FakeChatRepository repo, {int cardAfter = 10}) {
    final cardAt = base.add(Duration(minutes: cardAfter, seconds: 30));
    repo.seedIncoming(
      id: 't1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'Snakes and Ladders',
      createdAt: cardAt,
      mediaType: 'game_trail',
      gameSessionId: 's1',
    );
    repo.seedIncoming(
      id: 'g1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'Snakes and Ladders',
      createdAt: cardAt,
      sortAt: DateTime.now(),
      mediaType: 'game',
      gameSessionId: 's1',
    );
    repo.emitRealtime();
  }

  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        // No session stream in widget tests: the card shows its fallback
        // title, which is all the motion needs.
        gameCardProvider.overrideWith((ref, id) => const Stream.empty()),
      ],
    );
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
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  /// The SettleIn fade opacity of the row containing [rowContent], or null
  /// while that row is not built.
  double? settleOpacity(WidgetTester tester, Finder rowContent) {
    if (rowContent.evaluate().isEmpty) return null;
    final fade = find.descendant(
      of: find.ancestor(of: rowContent, matching: find.byType(SettleIn)).first,
      matching: find.byType(FadeTransition),
    );
    return tester.widget<FadeTransition>(fade.first).opacity.value;
  }

  testWidgets('at the newest end the moved card settles in at the bottom and '
      'the trail just appears', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedHistory(repo, count: 6, cardAfter: 2);
    final container = await pumpChat(tester, repo);
    final card = find.byType(GameMessageBubble);
    final trail = find.byType(GameTrailLine);
    expect(card, findsOneWidget);
    expect(trail, findsNothing);
    expect(settleOpacity(tester, card), 1.0, reason: 'history never animates');

    partnerMoves(repo, cardAfter: 2);
    var cardMin = 1.0;
    var trailMin = 1.0;
    var trailSeen = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final c = settleOpacity(tester, card);
      if (c != null && c < cardMin) cardMin = c;
      final t = settleOpacity(tester, trail);
      if (t != null) {
        trailSeen = true;
        if (t < trailMin) trailMin = t;
      }
    }
    final convo = activeConversation('rel-1');
    final newest = container.read(chatControllerProvider(convo)).messages.first;
    final cardFinal = settleOpacity(tester, card);
    await tearDownChat(tester, container);

    expect(newest.id, 'g1', reason: 'the card moved to the newest slot');
    expect(trailSeen, isTrue);
    expect(
      trailMin,
      1.0,
      reason: 'a trail marks where the card WAS; it never animates',
    );
    expect(
      cardMin,
      lessThan(0.5),
      reason: 'the moved card must settle into its new slot like an arrival',
    );
    expect(cardFinal, 1.0, reason: 'and finish settled');
  });

  testWidgets('scrolled up, a partner move from above the reading row to the '
      'bottom does not move the row being read', (tester) async {
    // R4: the card keeps its row-${message.id} key while changing index;
    // the trail lands where it was. The list anchor must hold the reader.
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedHistory(repo, count: 40, cardAfter: 10);
    final container = await pumpChat(tester, repo);

    await tester.drag(find.byType(ListView), const Offset(0, 900));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    String? anchor;
    for (var i = 39; i >= 0; i--) {
      final f = find.text('message $i');
      if (f.evaluate().isEmpty) continue;
      final rect = tester.getRect(f);
      if (rect.top > 200 && rect.bottom < 1000) {
        anchor = 'message $i';
        break;
      }
    }
    expect(anchor, isNotNull, reason: 'test needs a fully visible row');
    final anchorIndex = int.parse(anchor!.split(' ').last);
    expect(
      anchorIndex,
      greaterThan(10),
      reason: 'the card must sit above (older than) the row being read',
    );
    final before = tester.getTopLeft(find.text(anchor));

    partnerMoves(repo, cardAfter: 10);
    var worst = 0.0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final dy = tester.getTopLeft(find.text(anchor)).dy;
      if ((dy - before.dy).abs() > worst) worst = (dy - before.dy).abs();
    }
    final convo = activeConversation('rel-1');
    final newest = container.read(chatControllerProvider(convo)).messages.first;
    await tearDownChat(tester, container);

    expect(newest.id, 'g1', reason: 'the move landed');
    expect(worst, lessThan(1), reason: 'the reader must not move');
  });

  testWidgets('scrolled up, a partner move from below the reading row to the '
      'bottom does not move the row being read', (tester) async {
    // The trail is inserted BELOW the reader here, so the hold has to
    // cancel its height too.
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedHistory(repo, count: 40, cardAfter: 36);
    final container = await pumpChat(tester, repo);

    await tester.drag(find.byType(ListView), const Offset(0, 900));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    String? anchor;
    for (var i = 0; i < 40; i++) {
      final f = find.text('message $i');
      if (f.evaluate().isEmpty) continue;
      final rect = tester.getRect(f);
      if (rect.top > 200 && rect.bottom < 1000) {
        anchor = 'message $i';
        break;
      }
    }
    expect(anchor, isNotNull, reason: 'test needs a fully visible row');
    final anchorIndex = int.parse(anchor!.split(' ').last);
    expect(
      anchorIndex,
      lessThanOrEqualTo(36),
      reason: 'the card must sit below (newer than) the row being read',
    );
    final before = tester.getTopLeft(find.text(anchor));

    partnerMoves(repo, cardAfter: 36);
    var worst = 0.0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final dy = tester.getTopLeft(find.text(anchor)).dy;
      if ((dy - before.dy).abs() > worst) worst = (dy - before.dy).abs();
    }
    final convo = activeConversation('rel-1');
    final newest = container.read(chatControllerProvider(convo)).messages.first;
    await tearDownChat(tester, container);

    expect(newest.id, 'g1', reason: 'the move landed');
    expect(worst, lessThan(1), reason: 'the reader must not move');
  });
}
