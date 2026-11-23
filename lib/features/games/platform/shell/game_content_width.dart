import 'dart:math' as math;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/widgets.dart';

/// Keeps a game in a centred column on a wide screen, and full width on a
/// phone.
///
/// It does what the app's `AppContentWidth` does, with one difference that
/// matters to a game: the widget tree is the same shape at every width.
/// `AppContentWidth` returns its child bare on a phone and wrapped in a
/// `Padding` on a wider screen, so turning a phone on its side, or
/// resizing a tablet's split view, swaps one for the other and Flutter
/// rebuilds everything underneath from nothing. For a game that is a
/// half-played board, or a typed answer, gone.
///
/// Here the `Padding` is always present, and is simply zero on a phone.
class GameContentWidth extends StatelessWidget {
  const GameContentWidth({
    super.key,
    this.maxWidth = ContentWidth.form,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side =
          constraints.hasBoundedWidth
              ? math.max(0.0, (constraints.maxWidth - maxWidth) / 2)
              : 0.0;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: side),
        child: child,
      );
    },
  );
}
