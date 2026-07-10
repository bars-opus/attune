import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to enabled, persists a toggle', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    expect(container.read(messageSoundsEnabledProvider), isTrue);

    await container.read(messageSoundsEnabledProvider.notifier).setEnabled(false);
    expect(container.read(messageSoundsEnabledProvider), isFalse);
    expect(prefs.getBool('chat_message_sounds_enabled'), isFalse);
  });
}
