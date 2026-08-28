import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Chat feel section exposes an expressiveness switch that persists',
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

    final finder = find.byKey(const ValueKey('expressive_moments_switch'));
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(container.read(chatExpressivenessProvider), ChatExpressiveness.calm);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(container.read(chatExpressivenessProvider),
        ChatExpressiveness.expressive);
  });
}
