// Spec 1 W3c (§2.4, §5.6 R7): under flow_paths_v2 notifications are asked
// for in context (R2, R4, J3), not after sign-in; a linked or paused couple
// keeps today's ask while flow_couples_v2 (whose R4 asks them) is off; a
// contextual ask opts the phone in, or opens Settings once the OS won't ask.
import 'dart:async';

import 'package:attune/core/notifications/data/owed_push_release_store.dart';
import 'package:attune/core/notifications/data/push_subscription_registry.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/notifications/services/push_sdk.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart'
    show chatConnectivityProvider;
import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_home_state.dart';

class _Sdk implements PushSdk {
  bool granted = false;
  bool canPrompt = true;
  bool grantOnRequest = true;

  /// B6 review I-1: the OS answers before the SDK's cached permission
  /// catches up (a separate observer message).
  bool lagCache = false;
  int prompts = 0;
  int optIns = 0;
  bool opted = false;
  String? subscription = 'sub-1';

  @override
  Future<void> initialize(String appId) async {}
  @override
  Future<void> login(String externalId) async {}
  @override
  Future<void> logout() async {}
  @override
  bool get permissionGranted => granted;
  @override
  Future<bool> canRequestPermission() async => canPrompt;
  @override
  Future<bool> requestPermission() async {
    prompts++;
    if (lagCache) {
      final answer = grantOnRequest;
      Future(() => granted = answer);
      return answer;
    }
    granted = grantOnRequest;
    return granted;
  }

  @override
  String? get subscriptionId => subscription;
  @override
  bool get optedIn => opted;
  @override
  Future<void> optIn() async {
    optIns++;
    opted = true;
  }

  @override
  Future<void> optOut() async => opted = false;
  @override
  void onSubscriptionChanged(void Function(String? id, bool optedIn) l) {}
}

class _Registry implements PushSubscriptionRegistry {
  int registers = 0;
  @override
  Future<void> register({
    required String subscriptionId,
    required String platform,
  }) async => registers++;
  @override
  Future<void> unregister(String subscriptionId) async {}
  @override
  Future<void> release(String subscriptionId) async {}
}

class _Owed implements OwedPushReleaseStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String subscriptionId) async {}
  @override
  Future<void> clear() async {}
}

/// B6 review M-4: a flags read that never answers.
class _HangingFlags implements FlowFlagsGateway {
  @override
  Future<SignedInFlowFlags> fetch() => Completer<SignedInFlowFlags>().future;
}

class _OpenLock extends SafetyLockController {
  @override
  SafetyLockState build() => SafetyLockState.open;
}

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
);

Future<
  ({
    ProviderContainer c,
    OneSignalService service,
    _Sdk sdk,
    _Registry registry,
    List<String> settings,
  })
>
_build({
  bool pathsV2 = true,
  bool couplesV2 = false,
  String? link,
  FlowFlagsGateway? flags,
}) async {
  SharedPreferences.setMockInitialValues({
    if (link != null)
      HomeStateStore.keyFor(
        'u1',
      ): '{"tab":"chat","link":"$link","needs":[],"hold":false,"at":"2026-10-26T08:00:00.000Z"}',
  });
  final prefs = await SharedPreferences.getInstance();
  final sdk = _Sdk();
  final registry = _Registry();
  final settings = <String>[];
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      signInFlowV2Provider.overrideWithValue(true),
      flowFlagsGatewayProvider.overrideWithValue(
        flags ?? FakeFlowFlagsGateway(pathsV2: pathsV2, couplesV2: couplesV2),
      ),
      owedPushReleaseStoreProvider.overrideWithValue(_Owed()),
      chatConnectivityProvider.overrideWith(
        (ref) => const Stream<bool>.empty(),
      ),
      authStateProvider.overrideWith((ref) => Stream.value(_user('u1'))),
      currentUserProvider.overrideWith((ref) => _user('u1')),
      safetyLockProvider.overrideWith(_OpenLock.new),
      pushSubscriptionRegistryProvider.overrideWithValue(registry),
      oneSignalServiceProvider.overrideWith(
        (ref) => OneSignalService(
          ref,
          sdk: sdk,
          platform: 'ios',
          openSettings: () async => settings.add('opened'),
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  return (
    c: c,
    service: c.read(oneSignalServiceProvider),
    sdk: sdk,
    registry: registry,
    settings: settings,
  );
}

void main() {
  test('the automatic ask, by flag and link', () {
    for (final (paths, couples, link, want) in [
      (false, false, null, true),
      (true, false, null, false),
      (true, false, LinkState.none, false),
      (true, false, LinkState.pending, false),
      (true, false, LinkState.linked, true),
      (true, false, LinkState.paused, true),
      (true, true, LinkState.linked, false),
    ]) {
      expect(
        automaticPushAskAllowed(pathsV2: paths, couplesV2: couples, link: link),
        want,
        reason: '$paths $couples $link',
      );
    }
  });

  test('flow_paths_v2 on: no prompt after sign-in for Just for me', () async {
    final t = await _build(link: 'none');
    await t.service.attach();
    expect(t.sdk.prompts, 0);
  });

  test(
    'flow_paths_v2 on: a linked couple keeps today\'s ask while couples v2 is off',
    () async {
      final t = await _build(link: 'linked');
      await t.service.attach();
      expect(t.sdk.prompts, 1);
    },
  );

  test('flow_paths_v2 off: today\'s ask', () async {
    final t = await _build(pathsV2: false, link: 'none');
    await t.service.attach();
    expect(t.sdk.prompts, 1);
  });

  test('in context: the OS dialog, then opted in and registered', () async {
    final t = await _build(link: 'none');
    await t.service.attach();
    expect(t.service.permissionGranted, isFalse);
    expect(
      await t.service.askInContext(PushAskContext.j3),
      PushAskOutcome.granted,
    );
    expect(t.sdk.prompts, 1);
    expect(t.sdk.optIns, 1);
    expect(t.registry.registers, greaterThanOrEqualTo(1));
    expect(
      await t.service.askInContext(PushAskContext.j3),
      PushAskOutcome.granted,
    );
    expect(t.sdk.prompts, 1, reason: 'granted: no second dialog');
  });

  test(
    'in context: declined is declined; a refused OS opens Settings',
    () async {
      final t = await _build(link: 'none');
      await t.service.attach();
      t.sdk.grantOnRequest = false;
      expect(
        await t.service.askInContext(PushAskContext.r2),
        PushAskOutcome.declined,
      );
      t.sdk.canPrompt = false;
      expect(
        await t.service.askInContext(PushAskContext.r2),
        PushAskOutcome.openedSettings,
      );
      expect(t.settings, ['opened']);
    },
  );

  test(
    'in context: a Yes counts while the SDK\'s cached permission lags (I-1)',
    () async {
      final t = await _build(link: 'none');
      await t.service.attach();
      t.sdk.lagCache = true;
      expect(
        await t.service.askInContext(PushAskContext.j3),
        PushAskOutcome.granted,
      );
      expect(t.sdk.prompts, 1);
      expect(t.sdk.optIns, 1);
      expect(t.registry.registers, greaterThanOrEqualTo(1));
    },
  );

  test(
    'an already-granted phone registers at once, not after the flags (M-4)',
    () async {
      final t = await _build(link: 'none', flags: _HangingFlags());
      t.sdk.granted = true;
      t.sdk.opted = true;
      await t.service.attach().timeout(const Duration(seconds: 1));
      expect(t.registry.registers, 1);
      expect(t.sdk.prompts, 0);
    },
  );
}
