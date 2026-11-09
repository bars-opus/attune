// Spec 2 W3a (§3.14; R1, R-8, R-10): the Dating routes. Each is a top-level
// route (no shell branch: quick exit's go() disposes it) with the same one
// redirect (signed in, then the Dating lock). A route is added here when
// its screen lands: W3a the steps and the unlock (Task 4: settings,
// not-open), W3c leave; W4-W9 theirs.
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/settings/dating_leave_screen.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class DatingPaths {
  static const unlock = datingUnlockPath;
  static const settings = '/dating/settings';
  static const notOpen = '/dating/not-open';
  static const leave = '/dating/leave';

  static String step(String step) => '/dating/setup/$step';

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
}) => GoRoute(
  path: path,
  name: name,
  redirect:
      (context, state) => datingRedirect(context, state, signedIn: signedIn()),
  pageBuilder:
      (context, state) => datingPage(
        state,
        // Fix round 1 (C-1): every page but the unlock is gated.
        path == DatingPaths.unlock
            ? screen(state)
            : DatingLockGate(
              pageKey: state.pageKey,
              from: state.uri.toString(),
              child: screen(state),
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
  ),
  datingRoute(
    DatingPaths.notOpen,
    'datingNotOpen',
    signedIn,
    (s) => DatingNotOpenScreen(
      country: s.uri.queryParameters['country'],
      region: s.uri.queryParameters['region'],
    ),
  ),
  datingRoute(
    DatingPaths.leave,
    'datingLeave',
    signedIn,
    (s) => const DatingLeaveScreen(),
    motion: (s) => DatingMotion.none,
  ),
];
