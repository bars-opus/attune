import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';

/// Pre-auth routes open while first launch is still on (Spec 1 §5.4).
const firstLaunchAllowedRoutes = <String>{
  RouteNames.welcome,
  RouteNames.signUp,
  RouteNames.guestAge,
  RouteNames.invite,
  RouteNames.ageStop,
  RouteNames.intro,
  RouteNames.safetyResources,
};

/// What X1's device block closes (spec §3.6, §5.4): every way to create an
/// account. "I already have an account" ([returningSignUpLocation]) stays
/// open (final review M-1): on a shared phone the block must not lock an
/// adult out of her own account. A number with no account goes to X1 from
/// there (SignUpCoordinator), never to N1's "Create an account".
const underAgeBlockedRoutes = <String>{
  RouteNames.signUp,
  RouteNames.invite,
  RouteNames.guestAge,
};

/// `/signup` the returning way: the one sign-up a blocked device opens.
final returningSignUpLocation =
    '${RouteNames.signUp}?entry=${SignUpEntry.returning.wire}';

/// Where a resumable sign-up is picked up from (W2b).
const _resumeFrom = <String>{
  '/_invisible',
  RouteNames.home,
  RouteNames.onboarding,
};

/// The routes only the v2 sign-in uses.
const flowV2OnlyRoutes = <String>{
  RouteNames.welcome,
  RouteNames.signUp,
  RouteNames.guestAge,
  RouteNames.invite,
  RouteNames.ageStop,
};

/// The app router's redirect (`createAppRouter`). Null: stay. [entry] is
/// the location's `entry` query parameter.
///
/// With flow_signin_v2 off it is today's rule, unchanged: first launch
/// shows IntroScreen and nothing else. The one addition is that a v2-only
/// route (reached only if the flag went off mid-session) goes home.
String? appRedirect(RoutingNotifier routing, String location, {String? entry}) {
  if (routing.flowV2) return flowV2Redirect(routing, location, entry: entry);

  if (location == '/_invisible') {
    return routing.isFirstLaunch ? RouteNames.intro : RouteNames.home;
  }

  if (routing.isFirstLaunch && location != RouteNames.intro) {
    return RouteNames.intro;
  }

  if (flowV2OnlyRoutes.contains(location)) return RouteNames.home;

  return null;
}

/// Under flow_signin_v2 (spec §5.4).
String? flowV2Redirect(
  RoutingNotifier routing,
  String location, {
  String? entry,
}) {
  final blocked = routing.underAgeBlocked;
  if (blocked &&
      underAgeBlockedRoutes.contains(location) &&
      !(location == RouteNames.signUp && entry == SignUpEntry.returning.wire)) {
    return RouteNames.ageStop;
  }
  // A sign-up in progress comes back where it stopped (W2b): at A4 after
  // the app was closed, or at A5 for an account A4 already verified, which
  // today's onboarding must never create without the date of birth. A
  // blocked device resumes only the returning way (M-1).
  if (_resumeFrom.contains(location) && routing.signUpToResume) {
    return blocked ? returningSignUpLocation : RouteNames.signUp;
  }
  if (location == '/_invisible') {
    return routing.isFirstLaunch ? RouteNames.welcome : RouteNames.home;
  }
  // Every legacy way to IntroScreen (sign-out, account deletion, the safety
  // sign-out) and to LoginScreen (OnboardingGate's signed-out branch) lands
  // on Welcome instead.
  if (location == RouteNames.intro || location == RouteNames.login) {
    return RouteNames.welcome;
  }
  if (routing.isFirstLaunch) {
    return firstLaunchAllowedRoutes.contains(location)
        ? null
        : RouteNames.welcome;
  }
  // A blocked device has no guest pass (ruling N-1): its guest /home goes
  // to G1, which the block turns into X1. In session too, before the next
  // boot reads the pass AgeGateStore.block() cleared.
  final guestPass = routing.guestAgeOk && !routing.underAgeBlocked;
  // G1 is once per install.
  if (location == RouteNames.guestAge && guestPass) {
    return RouteNames.home;
  }
  if (location == RouteNames.home && !routing.isSignedIn && !guestPass) {
    return RouteNames.guestAge;
  }
  return null;
}

/// Where main.dart's invite-link handler goes (spec §5.2, R3): under
/// flow_signin_v2 a signed-out invitee lands on RI-1; anyone signed in, and
/// everyone with the flag off, keeps today's /onboarding, whose gate
/// accepts the stored code.
String inviteLinkLocation(RoutingNotifier routing) =>
    routing.flowV2 && !routing.isSignedIn
        ? RouteNames.invite
        : RouteNames.onboarding;
