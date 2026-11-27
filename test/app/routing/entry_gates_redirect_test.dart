// Entry gates (owner 2026-11-27, fixes 5 and a): the router itself keeps
// a signed-in account that still owes the gate (consent, date of birth,
// name, path, or a hold) on /onboarding from any signed-in route, and a
// signed-out phone off the signed-in routes. A returning guest opens the
// guest home at launch. The exceptions stay: a sign-up in progress, the
// under-18 block (X1), the invite landing, safety and support, and the
// flow routes themselves.
import 'dart:convert';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_home_state.dart';

const _uid = 'u-gates';

/// Routes only a signed-in account may open.
const _signedInOnly = <String>[
  RouteNames.settings,
  RouteNames.signedInDevices,
  RouteNames.quietStates,
  RouteNames.planning,
  RouteNames.together,
  RouteNames.pulse,
  RouteNames.reflectionJournal,
  RouteNames.howYouUseAttune,
  RouteNames.birthDateSettings,
  RouteNames.invitePartner,
  RouteNames.notificationInbox,
  RouteNames.profileScreen,
  RouteNames.onboarding,
  '/games/hub',
];

/// Open while the account still owes the gate.
const _openWhileOwed = <String>[
  RouteNames.onboarding,
  // Fix round (review I-2): its own data and the child-safety report.
  RouteNames.dataExport,
  RouteNames.reportChildConcern,
  RouteNames.start,
  RouteNames.welcome,
  RouteNames.signUp,
  RouteNames.invite,
  RouteNames.ageStop,
  RouteNames.safetyResources,
  RouteNames.neutralScreen,
];

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<RoutingNotifier> _signedIn({
  List<String>? needs,
  bool hold = false,
  Map<String, Object> extra = const {},
}) async {
  final prefs = await _prefs(extra);
  if (needs != null) {
    await HomeStateStore(prefs, userId: _uid).write(
      HomeState.fromJson(homeJson(needs: needs, hold: hold)),
    );
  }
  return RoutingNotifier(prefs: prefs, flowV2: true, currentUserId: () => _uid);
}

Future<RoutingNotifier> _signedOut({bool guestOk = false}) async =>
    RoutingNotifier(
      prefs: await _prefs(),
      flowV2: true,
      guestAgeOk: guestOk,
      currentUserId: () => null,
    );

void main() {
  group('fix (a): a returning guest goes straight to the guest home', () {
    test('signed out with the guest pass: /home at launch', () async {
      expect(
        appRedirect(await _signedOut(guestOk: true), '/_invisible'),
        RouteNames.home,
      );
    });

    test('signed out without it: the intro', () async {
      expect(appRedirect(await _signedOut(), '/_invisible'), RouteNames.start);
    });

    test('first launch still opens the intro, a guest pass or not', () {
      final r = RoutingNotifier(
        isFirstLaunch: true,
        flowV2: true,
        guestAgeOk: true,
        currentUserId: () => null,
      );
      expect(appRedirect(r, '/_invisible'), RouteNames.start);
    });

    test('a blocked device still meets X1 (by way of G1), not Opinions', () {
      final r = RoutingNotifier(
        flowV2: true,
        guestAgeOk: true,
        underAgeBlocked: true,
        currentUserId: () => null,
      );
      expect(appRedirect(r, '/_invisible'), RouteNames.home);
      expect(appRedirect(r, RouteNames.home), RouteNames.guestAge);
      expect(appRedirect(r, RouteNames.guestAge), RouteNames.ageStop);
    });
  });

  group('fix 5: a signed-in account that still owes the gate', () {
    for (final needs in [
      ['consent'],
      ['birth_date'],
      ['name'],
      ['path'],
      ['birth_date', 'name', 'path'],
      ['something_new'],
    ]) {
      test('needs $needs: every signed-in route goes to /onboarding', () async {
        final r = await _signedIn(needs: needs);
        for (final location in [RouteNames.home, ..._signedInOnly]) {
          expect(
            appRedirect(r, location),
            location == RouteNames.onboarding ? isNull : RouteNames.onboarding,
            reason: location,
          );
        }
      });
    }

    test('fix round (review I-2): owed or held, the account can still '
        'download its data and report a concern about a child; a guest '
        'still can\'t', () async {
      for (final r in [
        await _signedIn(needs: const ['consent']),
        await _signedIn(needs: const [], hold: true),
      ]) {
        for (final location in [
          RouteNames.dataExport,
          RouteNames.reportChildConcern,
        ]) {
          expect(appRedirect(r, location), isNull, reason: location);
        }
      }
      final guest = await _signedOut(guestOk: true);
      expect(appRedirect(guest, RouteNames.dataExport), RouteNames.home);
      expect(appRedirect(guest, RouteNames.reportChildConcern), RouteNames.home);
      expect(appRedirect(await _signedOut(), RouteNames.dataExport), RouteNames.start);
    });

    test('a hold: every signed-in route goes to the gate (H1)', () async {
      final r = await _signedIn(needs: const [], hold: true);
      for (final location in [RouteNames.home, RouteNames.settings]) {
        expect(appRedirect(r, location), RouteNames.onboarding);
      }
    });

    test('the gate, the flow, safety and support stay open', () async {
      final r = await _signedIn(needs: const ['consent', 'birth_date']);
      for (final location in _openWhileOwed) {
        expect(appRedirect(r, location), isNull, reason: location);
      }
    });

    test('RI-3 stays open while only the path is owed (the gate sends '
        'a stored invite there), never before the name', () async {
      expect(
        appRedirect(await _signedIn(needs: const ['path']), RouteNames.joinInvite),
        isNull,
      );
      expect(
        appRedirect(
          await _signedIn(needs: const ['name', 'path']),
          RouteNames.joinInvite,
        ),
        RouteNames.onboarding,
      );
    });

    test('complete: nothing changes', () async {
      final r = await _signedIn(needs: const []);
      for (final location in [RouteNames.home, ..._signedInOnly]) {
        expect(appRedirect(r, location), isNull, reason: location);
      }
    });

    test('nothing known yet (no answer cached): the gate and HomeScreen '
        'decide, the router lets it through', () async {
      final r = await _signedIn();
      expect(appRedirect(r, RouteNames.settings), isNull);
      expect(appRedirect(r, RouteNames.home), isNull);
    });

    test('a queued A5 counts as given: only the path is left', () async {
      final r = await _signedIn(
        needs: const ['consent', 'birth_date', 'name', 'path'],
        extra: {
          'attune.onboarding.${OnboardingStore.userScopePrefix}.$_uid'
                  '.pending_sign_up':
              jsonEncode({
                'display_name': 'Ama',
                'birth_date': '1996-04-02',
              }),
        },
      );
      final home = r.localHome!;
      expect(home.needs, [HomeNeed.path]);
      expect(appRedirect(r, RouteNames.settings), RouteNames.onboarding);
      expect(appRedirect(r, RouteNames.joinInvite), isNull);
    });

    test('the gate going home once complete is never sent back (no loop)',
        () async {
      final prefs = await _prefs();
      final store = HomeStateStore(prefs, userId: _uid);
      await store.write(HomeState.fromJson(homeJson(needs: const ['name'])));
      final r = RoutingNotifier(
        prefs: prefs,
        flowV2: true,
        currentUserId: () => _uid,
      );
      expect(appRedirect(r, RouteNames.home), RouteNames.onboarding);
      // The gate's answer is cached before it goes home.
      await store.write(HomeState.fromJson(homeJson()));
      expect(appRedirect(r, RouteNames.home), isNull);
      expect(appRedirect(r, RouteNames.onboarding), isNull);
    });

    test('a sign-up in progress still resumes first', () async {
      // Covered by sign_in_redirect_test's W2b group: the resume rule runs
      // before this one, so an owed account mid-A5 resumes at /signup.
      final r = await _signedIn(needs: const ['consent']);
      expect(appRedirect(r, RouteNames.signUp), isNull);
    });
  });

  group('fix 5: a signed-out phone stays off the signed-in routes', () {
    test('no guest pass: the intro', () async {
      final r = await _signedOut();
      for (final location in _signedInOnly) {
        expect(appRedirect(r, location), RouteNames.start, reason: location);
      }
      // Unchanged: guest /home without the pass meets G1.
      expect(appRedirect(r, RouteNames.home), RouteNames.guestAge);
    });

    test('a guest: the guest home', () async {
      final r = await _signedOut(guestOk: true);
      for (final location in _signedInOnly) {
        if (location == RouteNames.settings) continue;
        expect(appRedirect(r, location), RouteNames.home, reason: location);
      }
    });

    test('a guest keeps the guest home, Opinions, guest Settings and the '
        'app settings it links to', () async {
      final r = await _signedOut(guestOk: true);
      for (final location in [
        RouteNames.home,
        RouteNames.settings,
        RouteNames.language,
        RouteNames.theme,
        RouteNames.appIcon,
        RouteNames.licenses,
        RouteNames.allLegalDocumentation,
        RouteNames.appInfoScreen,
        RouteNames.commentThread,
        RouteNames.anonymousProfile,
        RouteNames.opinionEngagement,
        RouteNames.tagBrowse,
        RouteNames.opinionLoader,
        RouteNames.editOpinion,
        RouteNames.quoteCompose,
      ]) {
        expect(appRedirect(r, location), isNull, reason: location);
      }
    });

    test('the flow, the invite landing, safety and quick exit stay open',
        () async {
      for (final r in [await _signedOut(), await _signedOut(guestOk: true)]) {
        for (final location in [
          RouteNames.start,
          RouteNames.welcome,
          RouteNames.signUp,
          RouteNames.invite,
          RouteNames.ageStop,
          RouteNames.safetyResources,
          RouteNames.neutralScreen,
        ]) {
          expect(appRedirect(r, location), isNull, reason: location);
        }
      }
    });
  });

  group('fix 4: the invite link', () {
    test('signed out opens RI-1 whatever flow_signin_v2 says', () {
      for (final flowV2 in [true, false]) {
        expect(
          inviteLinkLocation(
            RoutingNotifier(flowV2: flowV2, currentUserId: () => null),
          ),
          RouteNames.invite,
        );
        expect(
          inviteLinkLocation(
            RoutingNotifier(flowV2: flowV2, currentUserId: () => _uid),
          ),
          RouteNames.onboarding,
        );
      }
    });
  });
}
