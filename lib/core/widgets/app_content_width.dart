import 'dart:math' as math;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// Keeps [child] no wider than [maxWidth], centred, on a big screen; on a
/// phone it's the full width. Only the width is capped — height, and any
/// background behind this, still fill the space. See [ContentWidth].
class AppContentWidth extends StatelessWidget {
  const AppContentWidth({
    super.key,
    this.maxWidth = ContentWidth.list,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  /// A full-screen list view's [base] padding plus the side margin that
  /// puts its rows in the column — so it still scrolls from anywhere on the
  /// screen. On a phone it's [base] unchanged.
  static EdgeInsets padded(
    BuildContext context,
    EdgeInsets base, {
    double maxWidth = ContentWidth.list,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(0.0, (width - maxWidth) / 2);
    return base + EdgeInsets.symmetric(horizontal: side);
  }

  // Narrower than the cap (a phone): the child exactly as it was. Wider:
  // even side padding, so the child keeps the parent's height constraints.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || constraints.maxWidth <= maxWidth) {
        return child;
      }
      final side = (constraints.maxWidth - maxWidth) / 2;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: side),
        child: child,
      );
    },
  );
}

/// [AppContentWidth] for slivers: the list still scrolls from anywhere on
/// the screen, but [slivers] sit in the centred column.
class AppContentSliver extends StatelessWidget {
  const AppContentSliver({
    super.key,
    this.maxWidth = ContentWidth.list,
    required this.slivers,
  });

  final double maxWidth;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final side = math.max(0.0, (constraints.crossAxisExtent - maxWidth) / 2);
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: side),
        sliver: SliverMainAxisGroup(slivers: slivers),
      );
    },
  );
}
