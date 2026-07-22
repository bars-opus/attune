import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app shell's bottom navigation bar should be visible.
///
/// Shared across every scrollable tab (Discover, Following, Forums Explore,
/// Forums Contributing, ...) so any of them can hide the shell-level nav on
/// scroll-down and restore it on scroll-up, even though those screens sit
/// several widget-tree levels below HomeWidget (which actually renders the
/// nav bar). A single shared flag — rather than one per screen — also means
/// switching tabs mid-scroll can't leave the nav stuck hidden from a
/// different tab's scroll state.
final navVisibilityProvider = StateProvider<bool>((ref) => true);

/// Feeds scroll notifications from a scrollable's [NotificationListener] into
/// [navVisibilityProvider], converting raw scroll deltas into a hide/show
/// decision with a small dead zone so sub-pixel jitter (overscroll glow,
/// minor list reflow) doesn't flicker the nav bar.
///
/// Usage: wrap a screen's scrollable in a
/// `NotificationListener` of `UserScrollNotification`, and call
/// `NavVisibilityScrollHandler.handle(ref, notification)` from its callback.
class NavVisibilityScrollHandler {
  const NavVisibilityScrollHandler._();

  static bool handle(WidgetRef ref, UserScrollNotification notification) {
    switch (notification.direction) {
      case ScrollDirection.reverse: // finger moving up the screen -> content scrolling down
        ref.read(navVisibilityProvider.notifier).state = false;
      case ScrollDirection.forward: // finger moving down the screen -> content scrolling up
        ref.read(navVisibilityProvider.notifier).state = true;
      case ScrollDirection.idle:
        break;
    }
    return false;
  }
}
