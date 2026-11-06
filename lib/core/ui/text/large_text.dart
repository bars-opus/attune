import 'package:flutter/widgets.dart';

/// Large-text layout helpers (Spec 1 W10a). Each one is inert at the normal
/// text size, so a screen that uses them looks exactly as it was designed
/// until the phone's text size is turned up.

/// Whether the text here is scaled above 1.0.
bool isTextScaledUp(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 10;

/// A fixed-height column (an empty state, a stage screen's body) that
/// scrolls instead of overflowing once large text makes it taller than its
/// space. The column still fills the height, so its Spacers and centring
/// behave as before. Not for a child that holds a scrollable or a
/// LayoutBuilder (the column is measured by its intrinsic height), and not
/// where a parent measures intrinsic sizes itself (a sliver that fills the
/// rest of a feed, IntrinsicHeight, a Table): it lays out with a
/// LayoutBuilder, which can't answer them.
class ScrollWhenTall extends StatelessWidget {
  const ScrollWhenTall({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isTextScaledUp(context)) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return child;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}

/// A short readout in a fixed space (a timer, a count, a day number, a
/// gauge's figures) that shrinks to fit once large text makes it bigger
/// than its space, rather than overflowing or wrapping mid-number.
class ScaleDownToFit extends StatelessWidget {
  const ScaleDownToFit({
    super.key,
    required this.child,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (!isTextScaledUp(context)) return child;
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: child,
      ),
    );
  }
}

/// A sheet's column that scrolls once large text makes it taller than the
/// sheet allows; at the normal size it is returned as it is.
class ScrollWhenScaledUp extends StatelessWidget {
  const ScrollWhenScaledUp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      isTextScaledUp(context) ? SingleChildScrollView(child: child) : child;
}

/// The part of a fixed-height column that scrolls on its own at the normal
/// size (an Expanded scroll view). Once [ScrollWhenTall] scrolls the whole
/// column (large text) it is laid out in place instead: a column measured
/// by its intrinsic height can't hold a scroll view.
class ScrollsInPlaceUnlessScaledUp extends StatelessWidget {
  const ScrollsInPlaceUnlessScaledUp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      isTextScaledUp(context)
          ? child
          : Expanded(child: SingleChildScrollView(child: child));
}
