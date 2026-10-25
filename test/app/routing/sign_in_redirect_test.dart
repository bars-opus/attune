// Spec 1 W2a (§5.4, R2): the app router's redirect. With flow_signin_v2 off
// it is today's rule for every existing route; with it on, the pre-auth
// allow-list, the guest gate and the under-18 block.
import 'dart:convert';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

RoutingNotifier _routing({
  bool flowV2 = true,
  bool firstLaunch = false,
  bool signedIn = false,
  bool guestOk = false,
  bool blocked = false,
}) => RoutingNotifier(
  isFirstLaunch: firstLaunch,
  flowV2: flowV2,
  guestAgeOk: guestOk,
  underAgeBlocked: blocked,
  currentUserId: () => signedIn ? 'user-1' : null,
);

/// Routes that exist today, before Spec 1.
const _existing = [
  '/_invisible',
  RouteNames.intro,
  RouteNames.home,
  RouteNames.login,
  RouteNames.onboarding,
  RouteNames.settings,
  RouteNames.safetyResources,
  '/chatScreen',
];

/// Today's rule, written out, so the flag-off branch is compared with it.
String? _today(RoutingNotifier r, String location) {
  if (location == '/_invisible') {
    return r.isFirstLaunch ? RouteNames.intro : RouteNames.home;
  }
  if (r.isFirstLaunch && location != RouteNames.intro) return RouteNames.intro;
  return null;
}

void main() {
  group('flag off: today, byte for byte', () {
    for (final firstLaunch in [true, false]) {
      for (final signedIn in [true, false]) {
        test('first launch $firstLaunch, signed in $signedIn', () {
          final r = _routing(
            flowV2: false,
            firstLaunch: firstLaunch,
            signedIn: signedIn,
          );
          for (final location in _existing) {
            expect(
              appRedirect(r, location),
              _today(r, location),
              reason: location,
            );
          }
        });
      }
    }

    test('a v2-only route reached with the flag off goes where today goes', () {
      for (final location in flowV2OnlyRoutes) {
        expect(appRedirect(_routing(flowV2: false), location), RouteNames.home);
        expect(
          appRedirect(_routing(flowV2: false, firstLaunch: true), location),
          RouteNames.intro,
        );
      }
    });

    test('an invite link keeps today\'s /onboarding', () {
      expect(
        inviteLinkLocation(_routing(flowV2: false)),
        RouteNames.onboarding,
      );
    });
  });

  group('flag on', () {
    test('first launch opens Welcome, not IntroScreen', () {
      expect(
        appRedirect(_routing(firstLaunch: true), '/_invisible'),
        RouteNames.welcome,
      );
      expect(appRedirect(_routing(), '/_invisible'), RouteNames.home);
    });

    test('while first launch is on, only the pre-auth routes are open', () {
      final r = _routing(firstLaunch: true);
      for (final location in [
        RouteNames.welcome,
        RouteNames.signUp,
        RouteNames.guestAge,
        RouteNames.invite,
        RouteNames.ageStop,
        RouteNames.safetyResources,
      ]) {
        expect(appRedirect(r, location), isNull, reason: location);
      }
      for (final location in [
        RouteNames.home,
        RouteNames.onboarding,
        RouteNames.settings,
        RouteNames.login,
      ]) {
        expect(appRedirect(r, location), RouteNames.welcome, reason: location);
      }
    });

    test('every way to IntroScreen lands on Welcome', () {
      expect(appRedirect(_routing(), RouteNames.intro), RouteNames.welcome);
      expect(
        appRedirect(_routing(firstLaunch: true), RouteNames.intro),
        RouteNames.welcome,
      );
    });

    test('a signed-out guest who never passed G1 meets it before Opinions', () {
      expect(appRedirect(_routing(), RouteNames.home), RouteNames.guestAge);
      expect(appRedirect(_routing(guestOk: true), RouteNames.home), isNull);
      expect(appRedirect(_routing(signedIn: true), RouteNames.home), isNull);
    });

    test('G1 is once per install', () {
      expect(
        appRedirect(_routing(guestOk: true), RouteNames.guestAge),
        RouteNames.home,
      );
    });

    test('a blocked device has no guest pass: guest /home goes G1, then X1 '
        '(ruling N-1)', () {
      // In session, before the next boot reads the pass the block cleared.
      final blocked = _routing(guestOk: true, blocked: true);
      expect(appRedirect(blocked, RouteNames.home), RouteNames.guestAge);
      expect(appRedirect(blocked, RouteNames.guestAge), RouteNames.ageStop);
      // An unblocked device that passed G1 is unaffected.
      expect(appRedirect(_routing(guestOk: true), RouteNames.home), isNull);
    });

    test(
      'an under-18 block closes sign-up, invites and G1, even on first launch',
      () {
        for (final firstLaunch in [true, false]) {
          final r = _routing(
            blocked: true,
            firstLaunch: firstLaunch,
            guestOk: true,
          );
          for (final location in underAgeBlockedRoutes) {
            expect(
              appRedirect(r, location),
              RouteNames.ageStop,
              reason: location,
            );
          }
          expect(appRedirect(r, RouteNames.ageStop), isNull);
          expect(appRedirect(r, RouteNames.welcome), isNull);
        }
      },
    );

    test('final review M-1: a blocked device still signs in to an account it '
        'has; creating one stays closed', () {
      for (final firstLaunch in [true, false]) {
        final r = _routing(blocked: true, firstLaunch: firstLaunch);
        expect(
          appRedirect(r, RouteNames.signUp, entry: SignUpEntry.returning.wire),
          isNull,
          reason: '"I already have an account", first launch $firstLaunch',
        );
        for (final entry in [
          null,
          SignUpEntry.newAccount.wire,
          SignUpEntry.invite.wire,
          'Returning',
        ]) {
          expect(
            appRedirect(r, RouteNames.signUp, entry: entry),
            RouteNames.ageStop,
            reason: 'entry $entry, first launch $firstLaunch',
          );
        }
        for (final location in [RouteNames.invite, RouteNames.guestAge]) {
          expect(
            appRedirect(r, location, entry: SignUpEntry.returning.wire),
            RouteNames.ageStop,
            reason: location,
          );
        }
      }
      expect(returningSignUpLocation, '/signup?entry=returning');
    });

    test(
      'an invite link opens RI-1 when signed out, /onboarding when signed in',
      () {
        expect(inviteLinkLocation(_routing()), RouteNames.invite);
        expect(
          inviteLinkLocation(_routing(signedIn: true)),
          RouteNames.onboarding,
        );
      },
    );
  });

  test('RoutingNotifier notifies only on a real change', () {
    final r = _routing(flowV2: false);
    var notified = 0;
    r.addListener(() => notified++);
    r.setFlowV2(false);
    r.setGuestAgeOk(false);
    r.setUnderAgeBlocked(false);
    expect(notified, 0);
    r.setFlowV2(true);
    r.setGuestAgeOk(true);
    r.setUnderAgeBlocked(true);
    expect(notified, 3);
  });

  group('W2b: a sign-up in progress, and LoginScreen', () {
    late SharedPreferences prefs;
    final now = DateTime.now().toUtc();

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    RoutingNotifier withDraft(SignUpDraft draft, {String? userId}) {
      prefs.setString(SignUpDraftStore.key, jsonEncode(draft.toJson()));
      return RoutingNotifier(
        prefs: prefs,
        flowV2: true,
        guestAgeOk: true,
        currentUserId: () => userId,
      );
    }

    final codeSent = SignUpDraft.start(
      SignUpEntry.newAccount,
      now: now,
    ).copyWith(phoneE164: '+233244123456', lastSentAt: now, sendCount: 1);

    test(
      'a code on its way: launch, home and onboarding resume at /signup',
      () {
        final r = withDraft(codeSent);
        for (final location in [
          '/_invisible',
          RouteNames.home,
          RouteNames.onboarding,
        ]) {
          expect(appRedirect(r, location), RouteNames.signUp, reason: location);
        }
        expect(appRedirect(r, RouteNames.signUp), isNull);
      },
    );

    test(
      'verified and signed in as that account: back to A5, never today\'s onboarding',
      () {
        final r = withDraft(
          codeSent.copyWith(verifiedUserId: 'u1'),
          userId: 'u1',
        );
        expect(appRedirect(r, RouteNames.onboarding), RouteNames.signUp);
        expect(appRedirect(r, RouteNames.home), RouteNames.signUp);
      },
    );

    test('another account, no code, or no draft: nothing to resume', () {
      expect(
        appRedirect(
          withDraft(codeSent.copyWith(verifiedUserId: 'u1'), userId: 'u2'),
          RouteNames.home,
        ),
        isNull,
      );
      expect(
        appRedirect(
          withDraft(SignUpDraft.start(SignUpEntry.newAccount, now: now)),
          RouteNames.home,
        ),
        isNull,
      );
      expect(appRedirect(_routing(guestOk: true), RouteNames.home), isNull);
    });

    test('the flag off ignores a draft entirely', () {
      prefs.setString(SignUpDraftStore.key, jsonEncode(codeSent.toJson()));
      final r = RoutingNotifier(prefs: prefs, currentUserId: () => null);
      expect(appRedirect(r, RouteNames.home), isNull);
    });

    test('LoginScreen is replaced by Welcome', () {
      expect(appRedirect(_routing(), RouteNames.login), RouteNames.welcome);
      expect(appRedirect(_routing(flowV2: false), RouteNames.login), isNull);
    });

    test('C9: a block written after boot (the replay\'s under-18 stop) '
        'applies in this session', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final r = RoutingNotifier(
        prefs: prefs,
        flowV2: true,
        guestAgeOk: true,
        currentUserId: () => null,
      );
      expect(r.underAgeBlocked, isFalse);
      expect(appRedirect(r, RouteNames.signUp), isNull);
      expect(appRedirect(r, RouteNames.home), isNull);

      await AgeGateStore(prefs).block();
      expect(r.underAgeBlocked, isTrue);
      expect(appRedirect(r, RouteNames.signUp), RouteNames.ageStop);
      expect(
        appRedirect(r, RouteNames.home),
        RouteNames.guestAge,
        reason: 'the guest pass goes with the block (ruling N-1)',
      );
      expect(appRedirect(r, RouteNames.guestAge), RouteNames.ageStop);
    });

    test('final review M-1: on a blocked device a sign-in left at A4 resumes '
        'the returning way, the one sign-up the block opens', () async {
      await prefs.setString(
        AgeGateStore.blockUntilKey,
        now.add(const Duration(days: 3)).toIso8601String(),
      );
      final r = withDraft(codeSent.copyWith(entry: SignUpEntry.returning));
      for (final location in [
        '/_invisible',
        RouteNames.home,
        RouteNames.onboarding,
      ]) {
        expect(
          appRedirect(r, location),
          returningSignUpLocation,
          reason: location,
        );
      }
      expect(
        appRedirect(r, RouteNames.signUp, entry: SignUpEntry.returning.wire),
        isNull,
      );
    });

    test('C9: the block read from prefs ends with its date, on the '
        'notifier\'s clock', () async {
      await prefs.setString(
        AgeGateStore.blockUntilKey,
        now.add(const Duration(days: 3)).toIso8601String(),
      );
      expect(
        RoutingNotifier(prefs: prefs, flowV2: true).underAgeBlocked,
        isTrue,
      );
      expect(
        RoutingNotifier(
          prefs: prefs,
          flowV2: true,
          now: () => now.add(const Duration(days: 4)),
        ).underAgeBlocked,
        isFalse,
      );
    });
  });
}
