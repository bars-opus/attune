// lib/core/widgets/keep_mounted_cover.dart
import 'package:flutter/widgets.dart';

/// Shows [cover] over [child] while [obscured], without unmounting [child]
/// (stories Wave 3; 07b G7). The child keeps its State -- the Router, its
/// pages and pageless routes, sheets, dialogs, scroll positions and text
/// fields -- across an incoming call, Control Centre or an app switch.
///
/// While obscured the child is Offstage (laid out, but never painted or
/// hit-tested, so an OS snapshot and default finders see only the cover),
/// under TickerMode(false) (its animations stop) and ExcludeSemantics (a
/// screen reader cannot reach it). Media, cameras, recordings and read
/// receipts still have to stop themselves: see appContentVisibleProvider.
///
/// The tree has the same shape whether or not [obscured], so toggling it
/// never rebuilds [child]'s State.
class KeepMountedCover extends StatelessWidget {
  const KeepMountedCover({
    super.key,
    required this.obscured,
    required this.cover,
    required this.child,
  });

  final bool obscured;
  final Widget cover;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      // Non-directional, so it needs no Directionality above the Router.
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: obscured,
          child: TickerMode(
            enabled: !obscured,
            child: ExcludeSemantics(excluding: obscured, child: child),
          ),
        ),
        if (obscured) cover,
      ],
    );
  }
}
