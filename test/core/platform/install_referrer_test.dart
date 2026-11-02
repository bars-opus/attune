// Spec 1 W4b (§3.8 RI): the Play Install Referrer's invite code is stored
// once per install, like a link opened while signed out; never on iOS;
// never over a code already waiting; never throws.
import 'package:attune/core/platform/install_referrer.dart';
import 'package:attune/core/platform/install_referrer_prefill.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the code in a referrer string', () {
    expect(
      inviteCodeFromReferrer('utm_source=invite&invite_code=k7p2qm'),
      'K7P2QM',
    );
    expect(inviteCodeFromReferrer('invite_code=K7P2QM'), 'K7P2QM');
    expect(
      inviteCodeFromReferrer('utm_source=google-play&utm_medium=organic'),
      isNull,
    );
    expect(inviteCodeFromReferrer('invite_code=NOPE'), isNull);
    expect(inviteCodeFromReferrer(null), isNull);
    expect(inviteCodeFromReferrer('%%%'), isNull);
  });

  // Final review #1: a prefill for RI-1 only, never the claimable slot.
  test('Android, first launch: kept for RI-1 only, once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var reads = 0;
    Future<String?> source() async {
      reads++;
      return 'utm_source=invite&invite_code=K7P2QM';
    }

    expect(
      await readInstallReferrerInvite(prefs, source: source, isAndroid: true),
      'K7P2QM',
    );
    expect(InstallReferrerPrefill.read(prefs), 'K7P2QM');
    expect(
      OnboardingStore(
        prefs,
        scope: OnboardingStore.anonymousScope,
      ).pendingInviteCode,
      isNull,
    );
    // No account claims it at sign-in either.
    expect(
      OnboardingStore(
        prefs,
        scope: '${OnboardingStore.userScopePrefix}.u1',
      ).pendingInviteCode,
      isNull,
    );
    expect(
      await readInstallReferrerInvite(prefs, source: source, isAndroid: true),
      isNull,
    );
    expect(reads, 1);
    expect(prefs.getBool(kInstallReferrerReadKey), isTrue);
  });

  test('iOS: nothing is read', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var reads = 0;
    expect(
      await readInstallReferrerInvite(
        prefs,
        source: () async {
          reads++;
          return 'invite_code=K7P2QM';
        },
        isAndroid: false,
      ),
      isNull,
    );
    expect(reads, 0);
  });

  test('a link already waiting wins; a failing read never throws', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await OnboardingStore.storeInviteFromLink(prefs, 'LINK22');
    expect(
      await readInstallReferrerInvite(
        prefs,
        source: () async => 'invite_code=K7P2QM',
        isAndroid: true,
      ),
      isNull,
    );
    expect(
      OnboardingStore(
        prefs,
        scope: OnboardingStore.anonymousScope,
      ).pendingInviteCode,
      'LINK22',
    );
    SharedPreferences.setMockInitialValues({});
    final fresh = await SharedPreferences.getInstance();
    expect(
      await readInstallReferrerInvite(
        fresh,
        source: () async => throw StateError('no Play services'),
        isAndroid: true,
      ),
      isNull,
    );
  });

  // Batch-6 review I-1: the first launch of an update on a signed-in
  // install is not the install's first launch: its referrer is never
  // claimed, and never overwrites a code already waiting.
  test(
    'signed in at the first read (an update): nothing stored, marked read',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var reads = 0;
      expect(
        await readInstallReferrerInvite(
          prefs,
          source: () async {
            reads++;
            return 'invite_code=K7P2QM';
          },
          isAndroid: true,
          signedIn: true,
        ),
        isNull,
      );
      expect(
        OnboardingStore(
          prefs,
          scope: OnboardingStore.anonymousScope,
        ).pendingInviteCode,
        isNull,
      );
      expect(prefs.getBool(kInstallReferrerReadKey), isTrue);
      expect(reads, 0);
      // The signed-in account's own waiting code stays as it was.
      await OnboardingStore.storeInviteFromLink(prefs, 'LINK22', userId: 'u1');
      await prefs.remove(kInstallReferrerReadKey);
      expect(
        await readInstallReferrerInvite(
          prefs,
          source: () async => 'invite_code=K7P2QM',
          isAndroid: true,
          signedIn: true,
        ),
        isNull,
      );
      expect(
        OnboardingStore(
          prefs,
          scope: OnboardingStore.anonymousScope,
        ).pendingInviteCode,
        isNull,
      );
      expect(
        OnboardingStore(
          prefs,
          scope: '${OnboardingStore.userScopePrefix}.u1',
        ).pendingInviteCode,
        'LINK22',
      );
    },
  );

  test(
    'the mark survives the sign-out clear, so the code never comes back',
    () async {
      SharedPreferences.setMockInitialValues({kInstallReferrerReadKey: true});
      final prefs = await SharedPreferences.getInstance();
      await PreferencesService(prefs).clearUserData();
      expect(prefs.getBool(kInstallReferrerReadKey), isTrue);
    },
  );
}
