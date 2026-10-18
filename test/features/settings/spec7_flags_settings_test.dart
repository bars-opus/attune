// Spec 7 final review I-2: with their flags off (as in production until they
// launch), "Quiet for a while" and the "Thankful for you" switch do not show.
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/appreciation/data/appreciation_service.dart';
import 'package:attune/features/quiet_states/presentation/quiet_state_providers.dart';
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
      quietStatesEnabledProvider.overrideWith((ref) async => on),
      appreciationEnabledProvider.overrideWith((ref) async => on),
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
  testWidgets('flags off: neither shows', (t) async {
    await _pump(t, on: false);
    // Hide a period is a resurfacing control and stays (Task 2 ruling); it
    // sits beside where "Quiet for a while" would be.
    expect(await _shows(t, find.text('Hide a period')), isTrue);
    expect(find.text('Quiet for a while'), findsNothing);
    expect(await _shows(t, find.byKey(const ValueKey('thankful_phrasing_switch'))), isFalse);
  });

  testWidgets('flags on: both show', (t) async {
    await _pump(t, on: true);
    expect(await _shows(t, find.text('Quiet for a while')), isTrue);
    expect(await _shows(t, find.byKey(const ValueKey('thankful_phrasing_switch'))), isTrue);
  });
}
