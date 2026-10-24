// 02 #17: a retried reply never lands twice, and a stalled send ends.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  IconButton send(WidgetTester tester) => tester.widget<IconButton>(
    find.byKey(const ValueKey('story-reel-reply-send')),
  );

  String replyText(WidgetTester tester) =>
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('story-reel-reply-field')),
          )
          .controller!
          .text;

  testWidgets(
    'a retry after a lost answer reuses the message id and is not sent twice',
    (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      final rig = await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      rig.chat
        ..enforceUniqueClientId = true
        ..errorAfterCommit = StateError('answer lost');

      await typeReply(tester, 'so pretty');
      await sendReply(tester);
      expect(find.text('Could not send your reply.'), findsOneWidget);
      final firstId = rig.chat.lastSendArgs!.clientMessageId;

      await sendReply(tester);
      expect(rig.chat.lastSendArgs!.clientMessageId, firstId);
      expect(rig.chat.serverMessages, hasLength(1));
      expect(find.text('Reply sent'), findsOneWidget);
    },
  );

  testWidgets('a stalled send gives up after 30 seconds and can be retried', (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(active: kitItems(['a']));
    final rig = await pumpReel(
      tester,
      gateway: gateway,
      hold: const Duration(seconds: 30),
    );
    rig.chat
      ..enforceUniqueClientId = true
      ..sendResponseGates.add(Completer<void>());

    await typeReply(tester, 'hello');
    await sendReply(tester);
    expect(send(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 31));
    await settle(tester);
    expect(find.text('Could not send your reply.'), findsOneWidget);
    expect(send(tester).onPressed, isNotNull);

    await sendReply(tester);
    expect(find.text('Reply sent'), findsOneWidget);
    expect(rig.chat.serverMessages, hasLength(1));
  });

  testWidgets('changing the text after a failure sends it as a new message '
      '(regression guard)', (tester) async {
    final gateway = ScriptedReelGateway(active: kitItems(['a']));
    final rig = await pumpReel(
      tester,
      gateway: gateway,
      hold: const Duration(seconds: 30),
    );
    rig.chat.errorAfterCommit = StateError('answer lost');
    await typeReply(tester, 'first');
    await sendReply(tester);
    final firstId = rig.chat.lastSendArgs!.clientMessageId;

    await typeReply(tester, 'second');
    await sendReply(tester);
    expect(rig.chat.lastSendArgs!.clientMessageId, isNot(firstId));
  });

  // Batch-1 review, Minor 4: the reel moving on under an in-flight send (here
  // the failed photo's automatic retry) must not leave Send disabled.
  testWidgets('a send that lands after the reel restarted the story still '
      'finishes', (tester) async {
    final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
    final rig = await pumpReel(
      tester,
      gateway: gateway,
      hold: const Duration(seconds: 30),
      images: KitImages()..failing.add('a'),
    );
    final gate = Completer<void>();
    rig.chat.sendResponseGates.add(gate);

    await typeReply(tester, 'hello');
    await sendReply(tester);
    expect(send(tester).onPressed, isNull);

    // The first automatic retry (1 s) restarts the story under the send.
    await tester.pump(const Duration(milliseconds: 1500));
    await settle(tester);
    gate.complete();
    await settle(tester);

    expect(find.text('Reply sent'), findsOneWidget);
    expect(send(tester).onPressed, isNotNull);
    expect(replyText(tester), isEmpty);
  });

  // Batch-1 review, Minor 3: the partner deletes the story I am replying to.
  group('the story I am replying to is deleted', () {
    testWidgets('I am told, my text is kept, and Send goes to the story now '
        'shown', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      final rig = await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      await typeReply(tester, 'so pretty');
      expect(replyFocused(tester), isTrue);

      gateway.active.removeWhere((i) => i.id == 'a');
      gateway.emitSignal();
      await settle(tester);

      expect(shownItemId(tester), 'b');
      expect(replyFocused(tester), isFalse);
      expect(replyText(tester), 'so pretty');
      expect(
        find.text(
          'That story is no longer available. Your reply is still here.',
        ),
        findsOneWidget,
      );

      await sendReply(tester);
      expect(rig.chat.lastSendArgs!.storyItemId, 'b');
      expect(find.text('Reply sent'), findsOneWidget);
    });

    testWidgets('a reply already on its way reports its own result', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      final rig = await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      final gate = Completer<void>();
      rig.chat.sendResponseGates.add(gate);
      await typeReply(tester, 'so pretty');
      await sendReply(tester);

      gateway.active.removeWhere((i) => i.id == 'a');
      gateway.emitSignal();
      await settle(tester);
      expect(
        find.text(
          'That story is no longer available. Your reply is still here.',
        ),
        findsNothing,
      );

      gate.complete();
      await settle(tester);
      expect(find.text('Reply sent'), findsOneWidget);
      expect(send(tester).onPressed, isNotNull);
    });

    // Batch-5 review, Minor 2: the in-flight send fails after its story
    // went, so the person is told that, not only "Could not send".
    testWidgets('a reply on its way that fails after the delete says the '
        'story is gone and keeps the text', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      final rig = await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 90),
      );
      // The answer never comes; the send's own bound ends it as failed.
      rig.chat.sendResponseGates.add(Completer<void>());
      await typeReply(tester, 'so pretty');
      await sendReply(tester);

      gateway.active.removeWhere((i) => i.id == 'a');
      gateway.emitSignal();
      await settle(tester);
      expect(shownItemId(tester), 'b');

      await tester.pump(const Duration(seconds: 31));
      await settle(tester);
      expect(
        find.text(
          'That story is no longer available. Your reply is still here.',
        ),
        findsOneWidget,
      );
      expect(find.text('Could not send your reply.'), findsNothing);
      expect(replyText(tester), 'so pretty');
      expect(send(tester).onPressed, isNotNull);
    });
  });
}
