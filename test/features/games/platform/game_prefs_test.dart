import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  Future<ProviderContainer> container([
    Map<String, Object> stored = const {},
  ]) async {
    final prefs = await testPrefs(stored);
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('sound and vibration are on until someone turns them off', () async {
    final c = await container();

    expect(c.read(gamePrefsProvider), const GamePrefs());
    expect(c.read(gamePrefsProvider).sound, isTrue);
    expect(c.read(gamePrefsProvider).haptics, isTrue);
  });

  test('a stored choice is read back', () async {
    final c = await container({
      GamePrefsNotifier.soundKey: false,
      GamePrefsNotifier.hapticsKey: true,
    });

    expect(c.read(gamePrefsProvider).sound, isFalse);
    expect(c.read(gamePrefsProvider).haptics, isTrue);
  });

  test('turning sound off is kept, and leaves vibration alone', () async {
    final c = await container();

    c.read(gamePrefsProvider.notifier).setSound(false);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(gamePrefsProvider).sound, isFalse);
    expect(c.read(gamePrefsProvider).haptics, isTrue);
    expect(
      c.read(sharedPreferencesProvider).getBool(GamePrefsNotifier.soundKey),
      isFalse,
    );
  });

  test('turning vibration off is kept, and leaves sound alone', () async {
    final c = await container();

    c.read(gamePrefsProvider.notifier).setHaptics(false);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(gamePrefsProvider).haptics, isFalse);
    expect(c.read(gamePrefsProvider).sound, isTrue);
    expect(
      c.read(sharedPreferencesProvider).getBool(GamePrefsNotifier.hapticsKey),
      isFalse,
    );
  });
}
