import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('toggling the Message sounds switch flips the preference',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilConfig.builder(
        builder: (_) => const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(currentUserId: 'test-user'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(container.read(messageSoundsEnabledProvider), isTrue);

    final switchFinder = find.byKey(const ValueKey('message_sounds_switch'));
    await tester.scrollUntilVisible(switchFinder, 200);
    await tester.pumpAndSettle();

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(container.read(messageSoundsEnabledProvider), isFalse);
  });
}
