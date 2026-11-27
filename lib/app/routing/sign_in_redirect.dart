import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/onboarding/domain/home_state.dart'
    show HomeNeed;
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart'
    show HomeSnapshot;

/// Pre-auth routes open while first launch is still on (Spec 1 §5.4).
const firstLaunchAllowedRoutes = <String>{
  RouteNames.start,
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
  RouteNames.start,
  RouteNames.welcome,
  RouteNames.signUp,
  RouteNames.guestAge,
  RouteNames.invite,
  RouteNames.ageStop,
};

/// Open to anyone, signed in or not, whatever the account still owes
/// (entry gates fix 5): the sign-in flow itself, safety and support (the
/// support resources are this route with `?focus=`), and quick exit's
/// neutral screen.
const _openToEveryone = <String>{
  ...flowV2OnlyRoutes,
  RouteNames.safetyResources,
  RouteNames.neutralScreen,
};

/// What a guest (signed out, past G1) may open besides [_openToEveryone]:
/// the guest home (Opinions and Join Attune), Opinions' own screens, and
/// the guest Settings with the app settings it links to (SettingsScreen
/// hides everything that needs an account).
const _guestRoutes = <String>{
  RouteNames.home,
  RouteNames.settings,
  RouteNames.language,
  RouteNames.theme,
  RouteNames.appIcon,
  RouteNames.licenses,
  RouteNames.allLegalDocumentation,
  RouteNames.appInfoScreen,
  RouteNames.anonymousProfile,
  RouteNames.commentThread,
  RouteNames.editOpinion,
  RouteNames.quoteCompose,
  RouteNames.opinionEngagement,
  RouteNames.tagBrowse,
  RouteNames.opinionLoader,
};

/// What stays open while a signed-in account still owes the gate, besides
/// [_openToEveryone]: the gate, and the settings a safety exit and the
/// consent step's reading rely on. Fix round (review I-2): its own data
/// (Download my data) and the child-safety report, so someone who won't
/// take the new terms, or is held, keeps them; deleting the account is
/// the gate's own link (a confirmation sheet, no route).
const _openWhileOwed = <String>{
  RouteNames.onboarding,
  RouteNames.safetyPin,
  RouteNames.licenses,
  RouteNames.allLegalDocumentation,
  RouteNames.dataExport,
  RouteNames.reportChildConcern,
};

/// The app router's redirect (`createAppRouter`). Null: stay. [entry] is
/// the location's `entry` query parameter.
///
/// The new sign-in is the only one (2026-11-26: the old phone login and its
/// flag-off rules are gone), so this is [flowV2Redirect] whatever
/// flow_signin_v2 says.
String? appRedirect(RoutingNotifier routing, String location, {String? entry}) =>
    flowV2Redirect(routing, location, entry: entry);

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
  // A blocked device has no guest pass (ruling N-1): its guest /home goes
  // to G1, which the block turns into X1. In session too, before the next
  // boot reads the pass AgeGateStore.block() cleared.
  final guestPass = routing.guestAgeOk && !blocked;
  // 2026-11-26: the intro (`/start`) comes first; its Get started opens
  // Welcome. Anyone not signed in starts there at every launch, first or
  // not (owner: "I already have an account" marks first launch done, and a
  // restart before signing in must not land on the sign-up screens). A
  // sign-up in progress resumed above, before this. Entry gates (a, owner
  // 2026-11-27): a returning guest (past G1) opens the guest home instead.
  if (location == '/_invisible') {
    if (routing.isFirstLaunch) return RouteNames.start;
    if (routing.isSignedIn) return RouteNames.home;
    // A device under X1's block still meets X1 at launch, as before (by way
    // of /home and G1 below).
    return guestPass || blocked ? RouteNames.home : RouteNames.start;
  }
  // Every legacy way to IntroScreen (sign-out, account deletion, the safety
  // sign-out) and to LoginScreen (the gate's signed-out branch) lands on
  // the intro instead.
  if (location == RouteNames.intro || location == RouteNames.login) {
    return RouteNames.start;
  }
  if (routing.isFirstLaunch) {
    return firstLaunchAllowedRoutes.contains(location)
        ? null
        : RouteNames.start;
  }
  // G1 is once per install.
  if (location == RouteNames.guestAge && guestPass) {
    return RouteNames.home;
  }
  if (!routing.isSignedIn) {
    if (location == RouteNames.home && !guestPass) return RouteNames.guestAge;
    // Entry gates fix 5: signed out, the signed-in routes are closed; a
    // guest goes back to the guest home, anyone else to the intro.
    if (_openToEveryone.contains(location)) return null;
    if (guestPass) {
      return _guestRoutes.contains(location) ? null : RouteNames.home;
    }
    return RouteNames.start;
  }
  return _gateRedirect(routing.localHome, location);
}

/// Entry gates fix 5: a signed-in account whose home state still owes the
/// gate (consent, date of birth, name, path, a need this build doesn't
/// know, or a hold) opens nothing but the gate, from any route. RI-3
/// stays open while only the path is owed: the gate sends a stored invite
/// there, after the name (§5.2), and RI-3 itself sends anything else back.
/// [home] is null while nothing is known: HomeScreen and the gate decide.
/// The gate goes home only once the same state is complete, so this never
/// loops.
String? _gateRedirect(HomeSnapshot? home, String location) {
  if (home == null || home.isComplete) return null;
  if (_openToEveryone.contains(location) || _openWhileOwed.contains(location)) {
    return null;
  }
  if (location == RouteNames.joinInvite &&
      !home.hold &&
      home.needs.every((need) => need == HomeNeed.path)) {
    return null;
  }
  return RouteNames.onboarding;
}

/// Where main.dart's invite-link handler goes (spec §5.2, R3): a
/// signed-out invitee lands on RI-1, whatever flow_signin_v2 says (entry
/// gates fix 4: the new sign-in is the only one); anyone signed in opens
/// /onboarding, whose gate takes the stored code only after consent, the
/// date of birth and the name (under flow_couples_v2 it opens RI-3,
/// /join-invite, which joins only after a tap: D9).
String inviteLinkLocation(RoutingNotifier routing) =>
    routing.isSignedIn ? RouteNames.onboarding : RouteNames.invite;
