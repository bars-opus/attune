// Spec 2 §3.0, §7.2 S19 (C-5, D20): using the Dating section, the not-open
// screen and Dating settings writes nothing to SharedPreferences and nothing
// to the secure store but Spec 1's own me_section_lock.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/flow_harness.dart';
import '../../helpers/tap_in_reach.dart';
import 'support/dating_fakes.dart';
import 'support/dating_shell.dart';

Future<void> _expectNothingWritten() async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in prefs.getKeys()) {
    expect(key.toLowerCase(), isNot(contains('dating')), reason: key);
    expect(
      '${prefs.get(key)}'.toLowerCase(),
      isNot(contains('dating')),
      reason: key,
    );
  }
  final secure = await const FlutterSecureStorage().readAll();
  expect(secure.keys.toSet().difference({'me_section_lock'}), isEmpty);
}

void main() {
  testWidgets('the section, the not-open screen and settings write nothing', (
    t,
  ) async {
    final home = FakeDatingHomeGateway(
      home: const DatingHome(
        state: DatingHomeState.countryClosed,
        country: 'NG',
        notice: DatingNotice(available: true),
      ),
    );
    await pumpFlowScreen(
      t,
      () => const Scaffold(body: SingleChildScrollView(child: DatingSection())),
      overrides: datingShellOverrides(home: home),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    await _expectNothingWritten();
    await t.pumpWidget(const SizedBox());
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: datingShellOverrides(home: home),
    );
    await _expectNothingWritten();
    await t.pumpWidget(const SizedBox());
    await pumpFlowScreen(
      t,
      () => const DatingSettingsScreen(),
      overrides: datingShellOverrides(home: home),
    );
    await tapInReach(t, find.text('Clear my answers to the three questions'));
    await t.pumpAndSettle();
    await _expectNothingWritten();
  });
}
