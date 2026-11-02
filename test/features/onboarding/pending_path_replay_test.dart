// Spec 1 W3a (§3.7, §3.14; batch-1 review #1, #7): the queued A6 replay.
// It waits for a queued A5, lands once, keeps the choice while offline or
// while the account isn't ready, drops it on any other refusal, and never
// overwrites a path the account chose meanwhile (another device).
import 'dart:async';

import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_account_gateway.dart';
import '../../helpers/fake_home_state.dart';

typedef _Replay =
    ({
      OnboardingSyncService sync,
      OnboardingStore store,
      FakeHomeStateGateway home,
      FakeAccountGateway accounts,
    });

/// A signed-in account that still owes A6, with [queued] waiting on the
/// phone. set_my_path answers the chosen path, nothing left to do.
Future<_Replay> _build({AppPath queued = AppPath.justMe}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = OnboardingStore(prefs, scope: 'user.u-replay');
  await store.savePendingPath(queued);
  final home = FakeHomeStateGateway(
    state: homeJson(path: null, needs: ['path']),
  );
  home.onSetPath = (params) {
    home.state = homeJson(path: params['p_path'] as String);
  };
  final accounts = FakeAccountGateway();
  final sync = OnboardingSyncService(
    accountService: AccountService(accounts),
    homeStateService: HomeStateService(home),
    onSignUpNotEligible: () async {},
  );
  return (sync: sync, store: store, home: home, accounts: accounts);
}

void main() {
  test('waits while the account itself (A5) is still owed', () async {
    final r = await _build();
    await r.store.savePendingSignUp(
      PendingSignUp(displayName: 'Ama', birthDate: DateTime.utc(1990)),
    );
    r.accounts.failWith = TimeoutException('offline');
    await r.sync.flush(r.store);
    expect(r.home.count('set_my_path'), 0);
    expect(r.store.pendingPath, AppPath.justMe);

    // The account lands: the path follows in the same flush.
    r.accounts.failWith = null;
    await r.sync.flush(r.store);
    expect(r.accounts.count('complete_sign_up'), 2);
    expect(r.home.count('set_my_path'), 1);
    expect(r.store.pendingPath, isNull);
  });

  test(
    'lands once: the answer is handed on, a second flush does nothing',
    () async {
      final r = await _build();
      final synced = <HomeState>[];
      await r.sync.flush(r.store, onPathSynced: synced.add);
      final writes = r.home.calls.where((c) => c.$1 == 'set_my_path').toList();
      expect(writes.single.$2, {'p_path': 'just_me', 'p_confirmed': false});
      expect(synced.single.path, AppPath.justMe);
      expect(r.store.pendingPath, isNull);

      final callsBefore = r.home.calls.length;
      await r.sync.flush(r.store, onPathSynced: synced.add);
      expect(r.home.calls.length, callsBefore, reason: 'nothing left to send');
      expect(synced, hasLength(1));
    },
  );

  test('a choice confirmed in a sheet is replayed confirmed (B3 #5)', () async {
    final r = await _build();
    await r.store.savePendingPath(AppPath.justMe, confirmed: true);
    await r.sync.flush(r.store);
    final writes = r.home.calls.where((c) => c.$1 == 'set_my_path').toList();
    expect(writes.single.$2, {'p_path': 'just_me', 'p_confirmed': true});
    expect(r.store.pendingPath, isNull);
    expect(r.store.pendingPathConfirmed, isFalse);
  });

  test('offline (the check or the write) keeps the choice', () async {
    final checkFails = await _build();
    checkFails.home.failAlways = TimeoutException('offline');
    await checkFails.sync.flush(checkFails.store);
    expect(checkFails.store.pendingPath, AppPath.justMe);

    final writeFails = await _build(queued: AppPath.relationship);
    writeFails.home.onSetPath = (_) => throw TimeoutException('slow');
    await writeFails.sync.flush(writeFails.store);
    expect(writeFails.home.count('set_my_path'), 1);
    expect(writeFails.store.pendingPath, AppPath.relationship);
  });

  test(
    'path:needs_signup keeps the choice (the account is not ready)',
    () async {
      final r = await _build();
      r.home.onSetPath =
          (_) => throw FakeHomeStateGateway.refusal('path:needs_signup');
      await r.sync.flush(r.store);
      expect(r.home.count('set_my_path'), 1);
      expect(r.store.pendingPath, AppPath.justMe);
    },
  );

  test('any other refusal drops it; the gate asks again', () async {
    for (final message in [
      'path:confirm_pause_dating',
      'path:relationship_open',
      'path:confirm_withdraw',
      'path:invalid',
    ]) {
      final r = await _build();
      final synced = <HomeState>[];
      r.home.onSetPath = (_) => throw FakeHomeStateGateway.refusal(message);
      await r.sync.flush(r.store, onPathSynced: synced.add);
      expect(r.store.pendingPath, isNull, reason: message);
      expect(synced, isEmpty, reason: message);
    }
  });

  test(
    'a path chosen meanwhile (another device) is never overwritten',
    () async {
      final r = await _build();
      // Relationship was chosen on another phone while this one was offline.
      r.home.state = homeJson(path: 'relationship');
      final synced = <HomeState>[];
      await r.sync.flush(r.store, onPathSynced: synced.add);
      expect(r.home.count('set_my_path'), 0);
      expect(r.store.pendingPath, isNull, reason: 'the stale choice goes');
      expect(synced.single.path, AppPath.relationship);
    },
  );
}
