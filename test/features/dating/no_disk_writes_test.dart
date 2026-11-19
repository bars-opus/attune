// Spec 2 §3.0, §7.2 S19 (C-5, D20): using the Dating section, the not-open
// screen and Dating settings writes nothing to SharedPreferences and nothing
// to the secure store but Spec 1's own me_section_lock.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/reverify_route.dart';
import 'package:attune/features/dating/verify/verify_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/flow_harness.dart';
import '../../helpers/tap_in_reach.dart';
import 'support/dating_fakes.dart';
import 'support/dating_shell.dart';
import 'support/dating_verify_fakes.dart';

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
  // Spec 2 W4b (T6 review M-9): these screens never run App.initState, so
  // the install id isn't here; a test that does (an app-level S19 test,
  // §7.2) allow-lists attune.install_id too: it is created at first launch
  // for everyone and is not a Dating key.
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

  // Spec 2 W4a Task 4 (D20, C-5): D11 through the video check and the ID
  // route writes nothing either.
  testWidgets('D11 writes nothing', (t) async {
    final gateway = FakeDatingVerificationGateway();
    gateway.answers['start'] = [datingStarted()];
    gateway.answers['complete'] = [datingOutcome(DatingVerifyOutcome.needsId)];
    gateway.answers['start_id'] = [datingStarted()];
    gateway.answers['complete_id'] = [
      datingOutcome(DatingVerifyOutcome.idPending),
    ];
    await pumpFlowScreen(
      t,
      () => DatingVerifyFlow(
        step: 'verify',
        onBack: () {},
        onDone: () {},
        onChangePhotos: () {},
      ),
      overrides: [
        ...datingShellOverrides(verification: gateway),
        datingCaptureLauncherProvider.overrideWithValue(FakeCaptureLauncher()),
      ],
    );
    await t.pumpAndSettle();
    await tapInReach(t, find.byKey(const ValueKey('dating_verify_consent')));
    await t.pump();
    await tapInReach(t, find.text('Start video check'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('Check with my ID'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('Passport'));
    await t.pump();
    await tapInReach(t, find.text('Continue'));
    await t.pumpAndSettle();
    expect(gateway.actionNames, [
      'start',
      'complete',
      'start_id',
      'complete_id',
    ]);
    await _expectNothingWritten();
  });

  // Spec 2 W4b Task 7 (D20, C-5): the re-check and Start again write
  // nothing either.
  testWidgets('the re-check and Start again write nothing', (t) async {
    final gateway = FakeDatingVerificationGateway(
      state: const DatingVerification(available: true, trustedDevice: false),
    );
    gateway.answers['reverify_start'] = [datingStarted()];
    gateway.answers['reverify_complete'] = [
      datingOutcome(DatingVerifyOutcome.verified),
    ];
    for (final variant in DatingReverifyVariant.values) {
      await t.pumpWidget(const SizedBox());
      await pumpFlowScreen(
        t,
        () => const DatingReverifyRoute(),
        overrides: [
          ...datingShellOverrides(
            home: FakeDatingHomeGateway(
              home: DatingHome(
                state: DatingHomeState.reverifyDevice,
                reverifyVariant: variant,
              ),
            ),
            verification: gateway,
          ),
          datingCaptureLauncherProvider.overrideWithValue(
            FakeCaptureLauncher(),
          ),
        ],
      );
      await t.pumpAndSettle();
      await tapInReach(
        t,
        find.text(
          variant == DatingReverifyVariant.setupRestart
              ? 'Start again'
              : 'Start video check',
        ),
      );
      await t.pumpAndSettle();
      await _expectNothingWritten();
    }
    expect(gateway.actionNames, ['reverify_start', 'reverify_complete']);
  });
}
