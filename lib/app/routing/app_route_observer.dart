import 'package:flutter/widgets.dart';

/// The one navigator observer the app installs (see createAppRouter).
///
/// Screens that must know when another route is pushed over them — the
/// chat, whose read receipts and presence may only run while it is the
/// screen the person is looking at — subscribe with [RouteAware].
/// `State.deactivate` does not fire for a push (the covered route stays
/// mounted), which is why the chat used to mark messages read during a game.
///
/// A page pushed on top of a popup that is still open is not seen by the
/// screen under the popup (only the route directly below a push is told), so
/// pop a sheet or menu before pushing a page from it.
class AppRouteObserver extends RouteObserver<ModalRoute<void>> {
  /// The route most recently pushed anywhere on this navigator, and still on
  /// it. Read inside [RouteAware.didPushNext], which says THAT something was
  /// pushed over the subscriber but not what: a page covers the chat; a
  /// sheet, dialog or menu ([PopupRoute]) leaves it on screen with the
  /// person still in it. When that route leaves, this falls back to the
  /// route now on top (or null when that is not known).
  Route<dynamic>? lastPushedRoute;

  /// The route each pushed route went on top of, so a replacement can tell
  /// the route underneath what now covers it.
  final Expando<Route<dynamic>> _routeBelow = Expando<Route<dynamic>>();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
    if (previousRoute != null) _routeBelow[route] = previousRoute;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, lastPushedRoute)) lastPushedRoute = previousRoute;
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, lastPushedRoute)) lastPushedRoute = previousRoute;
    super.didRemove(route, previousRoute);
  }

  /// RouteObserver ignores replacements, so a sheet that replaces itself
  /// with a page (pushReplacement) would leave the chat under it believing
  /// only a popup is open. Report the new route as a push over the route the
  /// old one sat on: its subscribers get didPushNext and decide from
  /// [lastPushedRoute] whether they are covered.
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute == null) return;
    lastPushedRoute = newRoute;
    final below = oldRoute == null ? null : _routeBelow[oldRoute];
    if (below == null) return;
    _routeBelow[newRoute] = below;
    super.didPush(newRoute, below);
  }
}

final AppRouteObserver appRouteObserver = AppRouteObserver();
