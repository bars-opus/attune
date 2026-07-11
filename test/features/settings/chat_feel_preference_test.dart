import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to calm, persists a change', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    expect(container.read(chatExpressivenessProvider), ChatExpressiveness.calm);

    await container
        .read(chatExpressivenessProvider.notifier)
        .setExpressiveness(ChatExpressiveness.expressive);
    expect(container.read(chatExpressivenessProvider),
        ChatExpressiveness.expressive);
    expect(prefs.getString('chat_expressiveness'), 'expressive');
  });
}
