import 'package:attune/home/widgets/scroll_aware_fab.dart';
import 'package:flutter/material.dart';

/// The app's single floating action button — every screen that needs a FAB
/// (compose an opinion, submit a topic, log a moment, create a custom
/// question...) uses this instead of a raw FloatingActionButton, so the
/// color/shape/elevation stay in one place rather than drifting per screen.
///
/// Only [onPressed] and [icon] (plus, for the extended shape, [label]) vary
/// per caller — everything else is fixed app-wide.
class AppFab extends StatelessWidget {
  const AppFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
    this.heroTag,
    this.scrollAware = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;

  /// If set, renders as an extended FAB (icon + text pill) instead of the
  /// plain round icon-only FAB.
  final String? label;

  /// Required whenever more than one AppFab can be mounted in the same
  /// PageRoute subtree at once (e.g. sibling tabs kept alive together) —
  /// FloatingActionButton's default tag collides across them the instant
  /// either pushes a route ("multiple heroes share the same tag").
  final Object? heroTag;

  /// Wrap in ScrollAwareFab: hidden by default, shown only while the
  /// screen's scrollable content is actively scrolling down (mirrors the
  /// shell's bottom nav bar hiding on scroll — see nav_visibility_provider
  /// and scroll_aware_fab.dart). Off by default: most FABs (Timeline, custom
  /// question lists) stay always-visible; only feeds with a shared bottom
  /// nav to make room for opt in.
  final bool scrollAware;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final fab =
        label != null
            ? FloatingActionButton.extended(
              heroTag: heroTag,
              onPressed: onPressed,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              icon: Icon(icon),
              label: Text(label!),
            )
            : FloatingActionButton(
              heroTag: heroTag,
              onPressed: onPressed,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              child: Icon(icon),
            );

    return scrollAware ? ScrollAwareFab(child: fab) : fab;
  }
}
