import 'package:flutter/widgets.dart';

/// Hides the keyboard when a tap lands on empty space inside [child]: for
/// sheets and pages with text fields. Taps on fields, buttons and other
/// controls still go to them (the innermost control wins the tap), so only
/// a tap on nothing in particular puts the keyboard away.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Not an action for a screen reader: an unnamed tap on the whole
        // sheet fails labeledTapTargetGuideline (review B8 I-1).
        excludeFromSemantics: true,
        onTap: () => FocusScope.of(context).unfocus(),
        child: child,
      );
}
