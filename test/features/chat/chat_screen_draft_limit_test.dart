import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/games/invites/services/game_invite_service.dart';
import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _SpyGateway implements GameInviteGateway {
  int creates = 0;

  @override
  Future<GameInvite> create({
    required String relationshipId,
    required String gameType,
    required String idempotencyKey,
    String tone = 'connecting',
  }) async {
    creates++;
    return GameInvite(sessionId: 's1', existing: false);
  }

  @override
  Future<void> accept(String sessionId) async {}

  @override
  Future<void> decline(String sessionId) async {}
}

/// RC-16: _sendDraftText cleared the composer BEFORE sendMessage silently
/// refused an over-limit draft, so 10,001 characters vanished with no word.
void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: extraOverrides,
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

  FakeChatRepository seededRepo() {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hi',
      createdAt: DateTime.now(),
    );
    return repo;
  }

  testWidgets('typing/pasting past the limit trims and says so', (
    tester,
  ) async {
    final repo = seededRepo();
    final container = await pumpChat(tester, repo);

    final field = find.byType(TextField).first;
    await tester.enterText(field, 'x' * (Message.maxContentRunes + 1));
    await tester.pump(const Duration(milliseconds: 300));

    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text.runes.length, Message.maxContentRunes);
    expect(
      find.textContaining('10,000-character'),
      findsOneWidget,
      reason: 'the person must be told their text was trimmed',
    );
    await tester.pump(const Duration(seconds: 5));
    await tearDownChat(tester, container);
  });

  testWidgets('a paste in the middle of a long draft keeps the existing '
      'tail, trims only the insert, and tells the person', (tester) async {
    final repo = seededRepo();
    final container = await pumpChat(tester, repo);

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();
    final controller = tester.widget<TextField>(field).controller!;
    // Draft 100 under the limit with a recognisable tail; paste 500 at 50.
    final base =
        '${'a' * (Message.maxContentRunes - 210)}${'T' * 10}${'b' * 100}';
    final head = 'h' * 50;
    final draft = head + base.substring(50);
    controller.value = TextEditingValue(
      text: draft,
      selection: const TextSelection.collapsed(offset: 50),
    );
    await tester.pump(const Duration(milliseconds: 100));
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: head + 'p' * 500 + draft.substring(50),
        selection: const TextSelection.collapsed(offset: 550),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(controller.text.runes.length, Message.maxContentRunes);
    expect(controller.text.endsWith(draft.substring(50)), isTrue);
    expect(controller.text.startsWith(head), isTrue);
    expect(controller.selection.extentOffset, 50 + 100);
    expect(find.textContaining('10,000-character'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tearDownChat(tester, container);
  });

  testWidgets('rapid keystrokes at the limit show a single notice', (
    tester,
  ) async {
    final repo = seededRepo();
    final container = await pumpChat(tester, repo);

    final field = find.byType(TextField).first;
    final full = 'f' * Message.maxContentRunes;
    await tester.enterText(field, full);
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 4; i++) {
      await tester.enterText(field, '${full}g');
      await tester.pump(const Duration(milliseconds: 50));
    }
    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, full);
    expect(find.textContaining('10,000-character'), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('10,000-character'), findsNothing);

    // Still at the limit, seconds later: the same episode, so no second
    // notice (a time throttle would show one again here).
    await tester.enterText(field, '${full}g');
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.text, full);
    expect(find.textContaining('10,000-character'), findsNothing);

    // Below the limit, then over it again: a new episode, a new notice.
    await tester.enterText(field, full.substring(1));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(field, '${full}g');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('10,000-character'), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tearDownChat(tester, container);
  });

  testWidgets('an emoji straddling the limit is never split', (tester) async {
    final repo = seededRepo();
    final container = await pumpChat(tester, repo);

    final field = find.byType(TextField).first;
    // 9,999 code points + one emoji (code point 10,000) + one more.
    await tester.enterText(field, '${'z' * (Message.maxContentRunes - 1)}😀😀');
    await tester.pump(const Duration(milliseconds: 300));

    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text.runes.length, Message.maxContentRunes);
    expect(controller.text.endsWith('😀'), isTrue);
    expect(controller.text.runes.last, 0x1F600);
    await tester.pump(const Duration(seconds: 5));
    await tearDownChat(tester, container);
  });

  testWidgets('an over-limit draft set programmatically is kept, not sent', (
    tester,
  ) async {
    final repo = seededRepo();
    final container = await pumpChat(tester, repo);

    // _appendToComposer / the translator set controller.value directly,
    // bypassing input formatters — the send path must still refuse safely.
    final field = find.byType(TextField).first;
    final controller = tester.widget<TextField>(field).controller!;
    final tooLong = 'y' * (Message.maxContentRunes + 1);
    controller.value = TextEditingValue(
      text: tooLong,
      selection: TextSelection.collapsed(offset: tooLong.length),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.sendCallCount, 0);
    expect(controller.text, tooLong, reason: 'the draft must survive');
    expect(find.textContaining('10,000 characters'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tearDownChat(tester, container);
  });

  testWidgets('a staged game with an over-limit note is held, not sent', (
    tester,
  ) async {
    final repo = seededRepo();
    final gateway = _SpyGateway();
    final container = await pumpChat(
      tester,
      repo,
      extraOverrides: [gameInviteGatewayProvider.overrideWithValue(gateway)],
    );

    container.read(gameComposerProvider('rel-1').notifier).stage('mirror');
    await tester.pump(const Duration(milliseconds: 300));

    final field = find.byType(TextField).first;
    final controller = tester.widget<TextField>(field).controller!;
    final tooLong = 'n' * (Message.maxContentRunes + 1);
    controller.value = TextEditingValue(
      text: tooLong,
      selection: TextSelection.collapsed(offset: tooLong.length),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.sendCallCount, 0);
    expect(gateway.creates, 0, reason: 'the game must not go without its note');
    expect(controller.text, tooLong);
    expect(
      container.read(gameComposerProvider('rel-1')).isStaged,
      isTrue,
      reason: 'the game must stay staged with its refused note',
    );
    expect(find.textContaining('10,000 characters'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tearDownChat(tester, container);
  });

  testWidgets('the edit dialog trims a paste and refuses an over-limit save', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'teh typo',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('teh typo'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Edit'));
    await tester.pump(const Duration(milliseconds: 400));

    final dialogField = find.byType(TextField).last;
    await tester.enterText(dialogField, 'e' * (Message.maxContentRunes + 5));
    await tester.pump(const Duration(milliseconds: 100));
    final controller = tester.widget<TextField>(dialogField).controller!;
    expect(controller.text.runes.length, Message.maxContentRunes);

    // Programmatic over-limit text bypasses the formatter.
    final tooLong = 'q' * (Message.maxContentRunes + 1);
    controller.value = TextEditingValue(text: tooLong);
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Edit message'), findsOneWidget, reason: 'stays open');
    expect(controller.text, tooLong);
    expect(repo.editMessageCalls, isEmpty);
    expect(find.textContaining('10,000 characters'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    await tearDownChat(tester, container);
  });
}
