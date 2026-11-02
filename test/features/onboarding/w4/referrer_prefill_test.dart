// Final review #1 (safety): a Play Install Referrer code is a prefill only.
// It never reaches the claimable invite slot, so no screen accepts it, or
// opens RI-3 with it, without the person's own tap: with
// flow_couples_v2 off (today's production) or on. Only RI-1 reads it, to
// fill its code field; Continue is the person's step.
import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/platform/install_referrer.dart';
import 'package:attune/core/platform/install_referrer_prefill.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/invite_landing_screen.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-referrer';

/// A fresh Android install whose Play referrer carries someone's code
/// (a crafted link needs no invite page), as the boot read leaves prefs.
Future<Map<String, Object>> _freshInstallWithReferrer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await readInstallReferrerInvite(
    prefs,
    source: () async => 'utm_source=x&invite_code=K7P2QM',
    isAndroid: true,
  );
  return {for (final key in prefs.getKeys()) key: prefs.get(key)!};
}

void main() {
  for (final (name, signInV2, pathsV2, couplesV2) in [
    ('flow_signin_v2 off (today\'s production)', false, false, false),
    ('flow_couples_v2 off', true, true, false),
    ('flow_couples_v2 on', true, true, true),
  ]) {
    testWidgets('$name: the first sign-in never accepts a referrer code, '
        'nor opens RI-3 with it', (tester) async {
      final values = await _freshInstallWithReferrer();
      final invites = FakeInvites();
      await pumpHome(
        tester,
        userId: _uid,
        signInV2: signInV2,
        pathsV2: pathsV2,
        prefsValues: {
          ...values,
          'attune.onboarding.user.$_uid.completed': true,
        },
        server: homeJson(path: 'just_me'),
        overrides: [
          invitePartnerServiceProvider.overrideWithValue(invites),
          flowCouplesV2Provider.overrideWithValue(couplesV2),
        ],
        extraRoutes: [
          GoRoute(
            path: '/join-invite',
            builder: (_, __) => const Scaffold(body: Text('RI-3')),
          ),
        ],
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(invites.accepted, isEmpty);
      expect(find.text('RI-3'), findsNothing);
    });
  }

  testWidgets('RI-1 fills its code field; Continue is the person\'s step', (
    tester,
  ) async {
    final values = await _freshInstallWithReferrer();
    final h = await pumpFlowScreen(
      tester,
      () => const InviteLandingScreen(),
      prefsValues: values,
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'K7P2QM');
    expect(
      OnboardingStore(
        h.prefs,
        scope: OnboardingStore.anonymousScope,
      ).pendingInviteCode,
      isNull,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      OnboardingStore(
        h.prefs,
        scope: OnboardingStore.anonymousScope,
      ).pendingInviteCode,
      'K7P2QM',
    );
    // Used once: the prefill is gone.
    expect(h.prefs.containsKey(kInstallReferrerCodeKey), isFalse);
  });

  testWidgets('RI-1: a referrer code past a day fills nothing, and goes', (
    tester,
  ) async {
    final old = DateTime.now().toUtc().subtract(const Duration(hours: 25));
    final h = await pumpFlowScreen(
      tester,
      () => const InviteLandingScreen(),
      prefsValues: {
        kInstallReferrerCodeKey:
            '{"code":"K7P2QM","stored_at":"${old.toIso8601String()}"}',
      },
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(h.prefs.containsKey(kInstallReferrerCodeKey), isFalse);
  });

  test('wiped at sign-out and on quick exit', () async {
    final values = await _freshInstallWithReferrer();
    expect(values.containsKey(kInstallReferrerCodeKey), isTrue);
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    final entry = registry.entries.firstWhere(
      (e) => e.id == 'spec1.install_referrer_code',
    );
    expect(entry.moments, {WipeMoment.signOut, WipeMoment.quickExit});
    expect(entry.protective, isFalse);
    await entry.run();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kInstallReferrerCodeKey), isFalse);
    expect(InstallReferrerPrefill.read(prefs), isNull);
    // The read-once mark stays: the code never comes back.
    expect(prefs.getBool(kInstallReferrerReadKey), isTrue);
  });
}
