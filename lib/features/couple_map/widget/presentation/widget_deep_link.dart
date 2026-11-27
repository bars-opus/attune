// lib/features/couple_map/widget/presentation/widget_deep_link.dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart'
    show PlanningHomeTab, planningTabFromQuery;
import 'package:go_router/go_router.dart';

/// The distance widget's tap (widget spec §6.5). No ids: the app resolves
/// the couple itself. No `homeWidget` item: home_widget's iOS app-delegate
/// hook would claim it; app_links alone delivers this one.
const coupleWidgetLink = 'attune://planning?tab=map';

/// The Planning tab a link asks for, or null if it isn't a Planning link.
PlanningHomeTab? planningTabFromLink(Uri uri) {
  if (uri.scheme != 'attune' || uri.host != 'planning') return null;
  return planningTabFromQuery(uri.queryParameters['tab']);
}

/// Opens Planning on [tab] for a signed-in, paired person. Never over quick
/// exit's neutral screen (checked again after every await), never a second
/// copy, never with the flag off. True when it navigated.
///
/// [accountReady] is the router's own gate check (entry gates fix 5): the
/// account's home state, read fresh, owes nothing (consent, date of birth,
/// name, path) and has no hold. Otherwise, or if it can't be read, the
/// link opens the gate (`/onboarding`) instead.
Future<bool> openPlanningFromLink(
  GoRouter router,
  PlanningHomeTab tab, {
  required bool Function() signedIn,
  required Future<String?> Function() relationshipId,
  required Future<bool> Function() mapEnabled,
  required Future<bool> Function() accountReady,
}) async {
  // app_links delivers a cold-start link twice (getInitialLink and the
  // stream): one open at a time.
  if (_opening) return false;
  _opening = true;
  try {
    return await _open(
      router,
      tab,
      signedIn,
      relationshipId,
      mapEnabled,
      accountReady,
    );
  } finally {
    _opening = false;
  }
}

bool _opening = false;

Future<bool> _open(
  GoRouter router,
  PlanningHomeTab tab,
  bool Function() signedIn,
  Future<String?> Function() relationshipId,
  Future<bool> Function() mapEnabled,
  Future<bool> Function() accountReady,
) async {
  String path() => router.routerDelegate.currentConfiguration.uri.path;
  bool blocked() =>
      !signedIn() ||
      path() == RouteNames.neutralScreen ||
      path() == RouteNames.planning;
  if (blocked()) return false;
  bool ready;
  try {
    ready = await accountReady();
  } catch (_) {
    ready = false;
  }
  if (blocked()) return false;
  if (!ready) {
    // Fails closed: the gate shows what is owed (or that it couldn't check).
    if (path() != RouteNames.onboarding) router.go(RouteNames.onboarding);
    return false;
  }
  final String? rel;
  final bool flag;
  try {
    rel = await relationshipId();
    flag = await mapEnabled();
  } catch (_) {
    return false;
  }
  if (rel == null || !flag || blocked()) return false;
  router.push('${RouteNames.planning}?tab=${tab.name}', extra: rel);
  return true;
}
