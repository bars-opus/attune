// Spec 2 W3a (§3.14; R1, R-8, R-10): the Dating routes. Each is a top-level
// route (no shell branch: quick exit's go() disposes it) with the same one
// redirect (signed in, then the Dating lock). A route is added here when
// its screen lands: W3a the steps and the unlock (Task 4: settings,
// not-open), W3c leave; W4-W9 theirs.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/features/dating/chat/checkin_screen.dart';
import 'package:attune/features/dating/chat/conversations_screen.dart';
import 'package:attune/features/dating/chat/dating_chat_screen.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/report/restricted_screen.dart';
import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/settings/dating_leave_screen.dart';
import 'package:attune/features/dating/settings/abroad_screen.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/settings/never_introduce_screen.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/match_moment_screen.dart';
import 'package:attune/features/dating/today/today_screen.dart';
import 'package:attune/features/dating/verify/reverify_route.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class DatingPaths {
  static const unlock = datingUnlockPath;
  static const settings = '/dating/settings';
  static const notOpen = '/dating/not-open';
  static const leave = '/dating/leave';

  /// Spec 2 W4b (§3.3.4, §3.14): where every reverify_device answer leads.
  static const verify = '/dating/verify';

  /// Spec 2 W5b (§3.4, §3.5): Today and one match's moment.
  static const today = '/dating/today';

  /// Spec 2 W5c (§3.12): Never introduce me to these numbers.
  static const neverIntroduce = '/dating/never-introduce';

  /// Spec 2 W5c (§2.6, §3.12): Other countries.
  static const abroad = '/dating/abroad';

  static String match(String id) => '/dating/match/$id';

  /// Spec 2 W6a (§3.5, §3.6): the conversations list and one chat.
  static const chats = '/dating/chats';

  static String chat(String matchId) => '/dating/chat/$matchId';

  /// Spec 2 W6c (§3.6): the meeting kit, and where Check on me's push opens.
  static String plan(String matchId) => '/dating/chat/$matchId/plan';
  static const checkin = '/dating/checkin';

  /// Spec 2 W7a (§3.7): the restricted, hold and age-check screen.
  static const restricted = '/dating/restricted';

  static String step(String step) => '/dating/setup/$step';

  /// Spec 2 W5b (§3.4): an editor opened from Widen comes back to Today.
  static String stepFromToday(String step) => '/dating/setup/$step?from=today';

  static String notOpenFor({String? country, String? region}) =>
      Uri(
        path: notOpen,
        queryParameters: {
          if (country != null) 'country': country,
          if (region != null) 'region': region,
        },
      ).toString();
}

enum DatingMotion { sharedAxis, fade, none }

/// §3.15: D12's preview cross-fades in at 200 ms.
const kDatingCrossFade = Duration(milliseconds: 200);

/// §3.0, §3.15: D0, D4 and D13 never move; D12 cross-fades; every other
/// step is shared-axis X.
DatingMotion datingStepMotion(String step) => switch (step) {
  'wait' || 'privacy' || 'ready' => DatingMotion.none,
  'preview' => DatingMotion.fade,
  _ => DatingMotion.sharedAxis,
};

bool _reduceMotion() =>
    WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;

/// A Dating page: shared-axis X (30 dp, 300 ms forward, 250 ms back,
/// emphasized curves, mirrored right to left), a cross-fade, or nothing;
/// with reduce motion on, every moving page is a 150 ms cross-fade.
Page<void> datingPage(
  GoRouterState state,
  Widget child, {
  DatingMotion motion = DatingMotion.sharedAxis,
}) {
  if (motion == DatingMotion.none) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }
  final reduce = _reduceMotion();
  final fade = reduce || motion == DatingMotion.fade;
  final forward =
      reduce
          ? kReducedMotionFade
          : fade
          ? kDatingCrossFade
          : kStepForwardDuration;
  final back =
      reduce
          ? kReducedMotionFade
          : fade
          ? kDatingCrossFade
          : kStepBackDuration;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: forward,
    reverseTransitionDuration: back,
    transitionsBuilder: (context, animation, secondary, child) {
      if (fade) return FadeTransition(opacity: animation, child: child);
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Easing.emphasizedDecelerate,
        reverseCurve: Easing.emphasizedAccelerate,
      );
      return AnimatedBuilder(
        animation: curved,
        child: child,
        builder:
            (context, child) => Opacity(
              opacity: curved.value,
              child: Transform.translate(
                offset: Offset(
                  (rtl ? -kSharedAxisOffset : kSharedAxisOffset) *
                      (1 - curved.value),
                  0,
                ),
                child: child,
              ),
            ),
      );
    },
  );
}

GoRoute datingRoute(
  String path,
  String name,
  bool Function() signedIn,
  Widget Function(GoRouterState state) screen, {
  DatingMotion Function(GoRouterState state)? motion,
  // Spec 2 W6a fix round 1 (I-3): where back leads when this is the only page.
  String Function()? back,
}) => GoRoute(
  path: path,
  name: name,
  redirect:
      (context, state) => datingRedirect(context, state, signedIn: signedIn()),
  pageBuilder:
      (context, state) => datingPage(
        state,
        // Spec 2 W5b (§3.4): the photos leave memory with the last page.
        DatingPageWatch(
          // Fix round 1 (C-1): every page but the unlock is gated.
          child:
              path == DatingPaths.unlock
                  ? screen(state)
                  : DatingLockGate(
                    pageKey: state.pageKey,
                    from: state.uri.toString(),
                    child:
                        back == null
                            ? screen(state)
                            : DatingRootBack(to: back, child: screen(state)),
                  ),
        ),
        motion: motion?.call(state) ?? DatingMotion.none,
      ),
);

List<RouteBase> datingRoutes({required bool Function() signedIn}) => [
  datingRoute(
    DatingPaths.unlock,
    'datingUnlock',
    signedIn,
    (s) => DatingUnlockScreen(from: s.uri.queryParameters['from'] ?? ''),
  ),
  datingRoute(
    '/dating/setup/:step',
    'datingSetupStep',
    signedIn,
    (s) => DatingSetupStepRoute(
      step: s.pathParameters['step'] ?? '',
      from: datingStepFrom(s.uri.queryParameters['from']),
    ),
    motion: (s) => datingStepMotion(s.pathParameters['step'] ?? ''),
  ),
  datingRoute(
    DatingPaths.settings,
    'datingSettings',
    signedIn,
    (s) => const DatingSettingsScreen(),
    motion: (s) => DatingMotion.sharedAxis,
    back: datingMeLocation,
  ),
  // Final client fix (C-5): as the only page (the lock's return, a link),
  // not-open goes back to Me and leave to Dating settings.
  datingRoute(
    DatingPaths.notOpen,
    'datingNotOpen',
    signedIn,
    (s) => DatingNotOpenScreen(
      country: s.uri.queryParameters['country'],
      region: s.uri.queryParameters['region'],
    ),
    back: datingMeLocation,
  ),
  datingRoute(
    DatingPaths.leave,
    'datingLeave',
    signedIn,
    (s) => const DatingLeaveScreen(),
    motion: (s) => DatingMotion.none,
    back: () => DatingPaths.settings,
  ),
  // Spec 2 W4b: the check's outcomes are never animated (§3.0).
  datingRoute(
    DatingPaths.verify,
    'datingVerify',
    signedIn,
    (s) => const DatingReverifyRoute(),
    motion: (s) => DatingMotion.none,
  ),
  // Spec 2 W5b (§3.4, §3.15): Today slides in; the moment has its own
  // settle (§3.5), so its page doesn't move.
  datingRoute(
    DatingPaths.today,
    'datingToday',
    signedIn,
    (s) => const DatingTodayScreen(),
    motion: (s) => DatingMotion.sharedAxis,
    back: datingMeLocation,
  ),
  datingRoute(
    '/dating/match/:id',
    'datingMatch',
    signedIn,
    (s) => DatingMatchMomentScreen(
      matchId: s.pathParameters['id'] ?? '',
      moment: switch (s.extra) {
        (final DatingMoment m, _, _) => m,
        _ => null,
      },
      myName: switch (s.extra) {
        (_, final String name, _) => name,
        _ => null,
      },
      // T7 fix 1 (M-1): the account Today read the moment for.
      account: switch (s.extra) {
        (_, _, final String account) => account,
        _ => null,
      },
    ),
    motion: (s) => DatingMotion.none,
  ),
  // Spec 2 W5c (§3.12, §3.15): a standard list. Final client fix (C-5):
  // as the only page, both go back to Dating settings.
  datingRoute(
    DatingPaths.neverIntroduce,
    'datingNeverIntroduce',
    signedIn,
    (s) => const DatingNeverIntroduceScreen(),
    motion: (s) => DatingMotion.sharedAxis,
    back: () => DatingPaths.settings,
  ),
  datingRoute(
    DatingPaths.abroad,
    'datingAbroad',
    signedIn,
    (s) => const DatingAbroadScreen(),
    motion: (s) => DatingMotion.sharedAxis,
    back: () => DatingPaths.settings,
  ),
  // Spec 2 W6a (§3.5, §3.6, §3.15): the list is a standard list; the chat
  // slides in (its own messages never animate).
  datingRoute(
    DatingPaths.chats,
    'datingChats',
    signedIn,
    (s) => const DatingConversationsScreen(),
    motion: (s) => DatingMotion.sharedAxis,
    back: datingMeLocation,
  ),
  datingRoute(
    '/dating/chat/:matchId',
    'datingChat',
    signedIn,
    (s) => DatingChatScreen(matchId: s.pathParameters['matchId'] ?? ''),
    motion: (s) => DatingMotion.sharedAxis,
    back: () => DatingPaths.chats,
  ),
  // Spec 2 W6c (§3.6): nothing here moves. Task 10 ruling: as the only
  // page (the Dating lock's return, a link), the kit goes back to its chat
  // and the check-in (the push's go()) to home, as Not now does.
  datingRoute('/dating/chat/:matchId/plan', 'datingPlanMeet', signedIn, (s) {
    final id = s.pathParameters['matchId'] ?? '';
    return DatingRootBack(
      to: () => DatingPaths.chat(id),
      child: DatingPlanMeetScreen(matchId: id),
    );
  }),
  datingRoute(
    DatingPaths.checkin,
    'datingCheckin',
    signedIn,
    (s) => const DatingCheckinScreen(),
    back: () => RouteNames.home,
  ),
  // Spec 2 W7a (§3.7, §3.15): nothing here moves; alone, back is Me.
  datingRoute(
    DatingPaths.restricted,
    'datingRestricted',
    signedIn,
    (s) => const DatingRestrictedScreen(),
    back: datingMeLocation,
  ),
];
