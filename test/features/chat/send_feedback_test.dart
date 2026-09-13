import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('keyboard stays connected through optimistic send and ack', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a')
      ..sendDelay = const Duration(milliseconds: 120);
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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

    final field = find.byType(TextField);
    await tester.showKeyboard(field);
    await tester.enterText(field, 'first message');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    final sendGesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.send_rounded)),
    );
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
      reason: 'pressing the send control must remain inside the composer',
    );
    await sendGesture.up();
    await tester.pump(const Duration(milliseconds: 30));
    expect(repo.sendCallCount, 1);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.enterText(field, 'second message');
    await tester.pump();
    expect(find.text('second message'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.text('second message'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });

  testWidgets('sending a message fires exactly one light haptic', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fakeHaptics = FakeHaptics();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        hapticsProvider.overrideWithValue(fakeHaptics),
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

    expect(fakeHaptics.lightCount, 1);

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
