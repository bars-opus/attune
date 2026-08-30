import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('sending plays exactly one send sound when enabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fakeSound = FakeSoundService();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        soundServiceProvider.overrideWithValue(fakeSound),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 30));

    expect(fakeSound.played, [ChatSound.send]);

    // Let the view-active mark-as-read debounce (500ms) fire, then unmount
    // the widget tree before the container disposes so the controller's
    // keep-alive eviction Timer is cancelled via onCancel/onDispose instead
    // of racing the test binding's pending-timer check.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });

  testWidgets('sending plays no sound when the toggle is off', (tester) async {
    SharedPreferences.setMockInitialValues({
      'chat_message_sounds_enabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fakeSound = FakeSoundService();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        soundServiceProvider.overrideWithValue(fakeSound),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 30));

    expect(fakeSound.played, isEmpty);

    // Let the view-active mark-as-read debounce (500ms) fire, then unmount
    // the widget tree before the container disposes so the controller's
    // keep-alive eviction Timer is cancelled via onCancel/onDispose instead
    // of racing the test binding's pending-timer check.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });
}
