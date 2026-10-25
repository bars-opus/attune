import 'package:flutter/widgets.dart';

/// Lets the phone's own text size through to [child] (Spec 1 §2.3), up to
/// [maxScaleFactor] (2.0 by default) and never below 1.0.
///
/// The root shell clamps every route to 1.0 (`app_shell.dart`), and a nested
/// `MediaQuery.withClampedTextScaling` can't rise above its parent, so this
/// reads the scale straight from the view instead. Every Spec 1 screen is
/// wrapped in it from W2 onwards.
class AllowLargeText extends StatelessWidget {
  const AllowLargeText({
    super.key,
    required this.child,
    this.maxScaleFactor = 2.0,
  });

  final Widget child;
  final double maxScaleFactor;

  @override
  Widget build(BuildContext context) {
    final system = MediaQueryData.fromView(View.of(context)).textScaler;
    final data = MediaQuery.of(context);
    return MediaQuery(
      data: data.copyWith(
        textScaler: system.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: maxScaleFactor,
        ),
      ),
      child: child,
    );
  }
}
