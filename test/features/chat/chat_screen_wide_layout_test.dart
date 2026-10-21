// On an iPad the conversation — header, messages and message bar — sits in
// a centred 840pt column, while the wallpaper still fills the screen.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/attune_chat_wallpaper.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  Future<ProviderContainer> pumpChat(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
    return container;
  }

  Future<void> dispose(WidgetTester t, ProviderContainer c) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
    c.dispose();
  }

  testWidgets(
    'on an iPad the conversation is a centred column on the wallpaper',
    (t) async {
      final c = await pumpChat(t, const Size(1032, 1376));
      final field = t.getRect(find.byType(ChatTextField));
      expect(field.width, lessThanOrEqualTo(ContentWidth.chat));
      expect(field.center.dx, closeTo(1032 / 2, 1));
      final back = t.getRect(find.byType(BackButtonIcon).first);
      expect(back.left, greaterThanOrEqualTo((1032 - ContentWidth.chat) / 2));
      expect(t.getSize(find.byType(AttuneChatWallpaper)).width, 1032);
      await dispose(t, c);
    },
  );

  testWidgets('on a phone the message bar spans the screen as before', (
    t,
  ) async {
    final c = await pumpChat(t, const Size(390, 844));
    final field = t.getRect(find.byType(ChatTextField));
    expect(field.width, greaterThan(300));
    await dispose(t, c);
  });
}
