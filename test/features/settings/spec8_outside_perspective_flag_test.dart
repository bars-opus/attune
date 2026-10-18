// Spec 8 (B10; plan review P1, M10): the outside-perspective card carries
// clinician placeholders, so every way in stays closed until its flag
// (private_safety_check) is on.
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/safety/self_check/safety_self_check_service.dart';
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester t, {required bool on}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      safetySelfCheckEnabledProvider.overrideWith((ref) async => on),
    ],
    child: ScreenUtilConfig.builder(
      builder: (_) => const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(currentUserId: 'test-user'),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Future<bool> _shows(WidgetTester t, Finder f) async {
  try {
    await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  testWidgets('flag off: no Settings row', (t) async {
    await _pump(t, on: false);
    expect(await _shows(t, find.text('Safety resources')), isTrue);
    expect(await _shows(t, find.text('A trained outside perspective')), isFalse);
  });

  testWidgets('flag on: the Settings row shows', (t) async {
    await _pump(t, on: true);
    expect(await _shows(t, find.text('A trained outside perspective')), isTrue);
  });
}
