import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_test_harness.dart';

void main() {
  test('a new partner message while viewing plays one receive sound', () async {
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
        // The receive-haptic call sits right beside the sound call inside the
        // same guarded block; fake it out so a plain (non-widget) test isn't
        // tripped up by the platform channel needing a live Flutter binding.
        hapticsProvider.overrideWithValue(FakeHaptics()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.setViewActive(true);

    repo.seedIncoming(
      id: 'p1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hey',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(fakeSound.played, [ChatSound.receive]);
  });

  test('no receive sound while backgrounded', () async {
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
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // NOT setViewActive(true) → backgrounded.

    repo.seedIncoming(
      id: 'p1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hey',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(fakeSound.played, isEmpty);
  });
}
