// Spec 1 W1c (§5.5, research 10 S17): invite codes are scoped. A code opened
// while signed out is claimed by the next sign-in within 24 hours, once; a
// second account on the same phone never inherits it; the legacy unscoped
// key is moved once.
import 'dart:convert';

import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  DateTime clock() => now;

  setUp(() => now = DateTime.utc(2026, 10, 25, 9));

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  OnboardingStore user(SharedPreferences prefs, String uid) => OnboardingStore(
    prefs,
    scope: '${OnboardingStore.userScopePrefix}.$uid',
    now: clock,
  );

  test('signed out: the next sign-in within 24 h claims it, once', () async {
    final prefs = await prefsWith({});
    await OnboardingStore.storeInviteFromLink(prefs, 'K7P2QM', now: clock);
    expect(
      OnboardingStore(
        prefs,
        scope: OnboardingStore.anonymousScope,
      ).pendingInviteCode,
      'K7P2QM',
    );

    now = now.add(const Duration(hours: 23));
    expect(user(prefs, 'ama').pendingInviteCode, 'K7P2QM');
    expect(
      prefs.getString('attune.onboarding.anonymous.pending_invite'),
      isNull,
    );
    expect(user(prefs, 'kofi').pendingInviteCode, isNull);
    expect(user(prefs, 'ama').pendingInviteCode, 'K7P2QM');
  });

  test('a signed-out code older than 24 h is dropped, never claimed', () async {
    final prefs = await prefsWith({});
    await OnboardingStore.storeInviteFromLink(prefs, 'K7P2QM', now: clock);
    now = now.add(const Duration(hours: 24));
    expect(user(prefs, 'ama').pendingInviteCode, isNull);
    expect(
      prefs.getString('attune.onboarding.anonymous.pending_invite'),
      isNull,
    );
  });

  test(
    'signed in: straight to that account, invisible to anyone else',
    () async {
      final prefs = await prefsWith({});
      await OnboardingStore.storeInviteFromLink(
        prefs,
        'W7XK2P',
        userId: 'ama',
        now: clock,
      );
      final stored =
          jsonDecode(
                prefs.getString('attune.onboarding.user.ama.pending_invite')!,
              )
              as Map;
      expect(stored['code'], 'W7XK2P');
      expect(user(prefs, 'kofi').pendingInviteCode, isNull);
      expect(user(prefs, 'ama').pendingInviteCode, 'W7XK2P');

      await user(prefs, 'ama').clearPendingInviteCode();
      expect(user(prefs, 'ama').pendingInviteCode, isNull);
    },
  );

  test('the legacy unscoped key is moved once, then deleted', () async {
    final prefs = await prefsWith({
      OnboardingStore.pendingInviteCodeKey: 'LEG4CY',
    });
    expect(user(prefs, 'ama').pendingInviteCode, 'LEG4CY');
    expect(prefs.containsKey(OnboardingStore.pendingInviteCodeKey), isFalse);
    expect(user(prefs, 'kofi').pendingInviteCode, isNull);
  });

  // Batch 6 extra: the debug preview scope is not a sign-in, so it never sees
  // or claims a signed-out code; the next real sign-in still does.
  test('the preview scope never sees or claims a signed-out code', () async {
    final prefs = await prefsWith({});
    await OnboardingStore.storeInviteFromLink(prefs, 'K7P2QM', now: clock);
    final preview = OnboardingStore(
      prefs,
      scope: OnboardingStore.previewScope,
      now: clock,
    );
    expect(preview.pendingInviteCode, isNull);
    expect(user(prefs, 'ama').pendingInviteCode, 'K7P2QM');
  });

  // Batch 6 fix round 1, review #5: a signed-out code that can no longer be
  // claimed is dropped on an anonymous read too.
  test('an expired signed-out code is dropped on an anonymous read', () async {
    String stored(Duration age) => jsonEncode({
      'code': 'K7P2QM',
      'stored_at': now.subtract(age).toIso8601String(),
    });
    const key = 'attune.onboarding.anonymous.pending_invite';
    OnboardingStore anonymous(SharedPreferences prefs) => OnboardingStore(
      prefs,
      scope: OnboardingStore.anonymousScope,
      now: clock,
    );

    final fresh = await prefsWith({key: stored(const Duration(hours: 23))});
    expect(anonymous(fresh).pendingInviteCode, 'K7P2QM');
    expect(fresh.containsKey(key), isTrue);

    final expired = await prefsWith({key: stored(const Duration(hours: 24))});
    expect(anonymous(expired).pendingInviteCode, isNull);
    expect(expired.containsKey(key), isFalse);
  });

  test('reset clears the scope\'s code', () async {
    final prefs = await prefsWith({});
    await OnboardingStore.storeInviteFromLink(
      prefs,
      'W7XK2P',
      userId: 'ama',
      now: clock,
    );
    await user(prefs, 'ama').reset();
    expect(user(prefs, 'ama').pendingInviteCode, isNull);
  });
}
