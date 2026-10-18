// Spec 7 (plan ruling P2, review I7): "Thankful for you because…" is offered
// only when the person turns it on, on this device; it is never sent anywhere
// except as the words they choose.
import 'dart:io';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/appreciation/data/thankful_phrasing_preference.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('off by default, remembered on this device', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    expect(c.read(thankfulPhrasingProvider), isFalse);
    await c.read(thankfulPhrasingProvider.notifier).set(true);
    expect(prefs.getBool('appreciation_thankful_phrasing'), isTrue);
  });

  test('the Settings switch exists and the chat offers the phrasing from it', () {
    expect(File('lib/features/settings/screens/settings_screen.dart').readAsStringSync(),
        contains("ValueKey('thankful_phrasing_switch')"));
    expect(File('lib/features/chat/presentation/screens/chat_screen.dart').readAsStringSync(),
        contains('offerThankful: ref.read(thankfulPhrasingProvider)'));
  });
}
