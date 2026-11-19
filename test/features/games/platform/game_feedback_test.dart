import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/feel/game_feedback.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  late FakeSoundService sound;
  late FakeHaptics haptics;

  Future<ProviderContainer> container([
    Map<String, Object> stored = const {},
  ]) async {
    sound = FakeSoundService();
    haptics = FakeHaptics();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(await testPrefs(stored)),
        soundServiceProvider.overrideWithValue(sound),
        hapticsProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  int hapticTotal() =>
      haptics.lightCount + haptics.selectionCount + haptics.mediumCount;

  test('every event has a sound', () {
    // A new event added without a clip would otherwise fail at the moment
    // a player triggers it, not here.
    for (final event in GameEvent.values) {
      expect(
        GameFeedback.sounds.containsKey(event),
        isTrue,
        reason: '$event has no sound',
      );
    }
  });

  test('every event plays its sound and one tap you can feel', () async {
    final c = await container();
    final feedback = c.read(gameFeedbackProvider);

    for (final event in GameEvent.values) {
      feedback.fire(event);
    }

    expect(sound.played, [
      for (final event in GameEvent.values) GameFeedback.sounds[event],
    ]);
    expect(hapticTotal(), GameEvent.values.length);
  });

  test('bigger moments tap harder', () async {
    final c = await container();
    final feedback = c.read(gameFeedbackProvider);

    feedback.fire(GameEvent.tap);
    expect(haptics.selectionCount, 1);

    feedback.fire(GameEvent.place);
    expect(haptics.lightCount, 1);

    feedback.fire(GameEvent.complete);
    expect(haptics.mediumCount, 1);
  });

  test('sound off silences the clips but keeps the vibration', () async {
    final c = await container({GamePrefsNotifier.soundKey: false});

    c.read(gameFeedbackProvider).fire(GameEvent.match);

    expect(sound.played, isEmpty);
    expect(hapticTotal(), 1);
  });

  test('vibration off keeps the sound', () async {
    final c = await container({GamePrefsNotifier.hapticsKey: false});

    c.read(gameFeedbackProvider).fire(GameEvent.match);

    expect(sound.played, [AppSound.gameMatch]);
    expect(hapticTotal(), 0);
  });

  test('a change in settings applies to the very next event', () async {
    final c = await container();
    final feedback = c.read(gameFeedbackProvider);

    feedback.fire(GameEvent.tap);
    c.read(gamePrefsProvider.notifier).setSound(false);
    feedback.fire(GameEvent.tap);

    expect(sound.played, hasLength(1));
  });
}
