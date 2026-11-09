// Spec 2 W3 final fix (I-1b): the Dating sheets and dialogs that can open
// over Me carry a route name under one prefix, and each one is tracked
// while it is open. When the Dating unlock ends with the lock on, only
// these are removed, wherever they sit in the stack: a Spec 1 sheet on Me
// (Quizzes, Healing, the journal reminder, More ways) stays, with what was
// typed in it, even one opened over a Dating sheet.
import 'package:flutter/widgets.dart';

/// The route-name prefix every Me-hosted Dating sheet carries.
const datingSheetPrefix = 'dating-sheet/';

/// The route settings for the Dating sheet [name].
RouteSettings datingSheetSettings(String name) =>
    RouteSettings(name: '$datingSheetPrefix$name');

final _open = <Route<dynamic>>{};

/// Wraps a Dating sheet's body: its route is tracked while it is open.
class DatingSheetTracker extends StatefulWidget {
  const DatingSheetTracker({super.key, required this.child});

  final Widget child;

  @override
  State<DatingSheetTracker> createState() => _DatingSheetTrackerState();
}

class _DatingSheetTrackerState extends State<DatingSheetTracker> {
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    if (_route != null) _open.remove(_route);
    _route = route;
    if (route != null &&
        (route.settings.name?.startsWith(datingSheetPrefix) ?? false)) {
      _open.add(route);
    }
  }

  @override
  void dispose() {
    _open.remove(_route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Removes every open Dating sheet (and only those). A sheet above one
/// stays where it is; nothing of the Dating sheet is left to read.
void closeDatingSheets() {
  for (final route in List.of(_open)) {
    _open.remove(route);
    final navigator = route.navigator;
    if (route.isActive && navigator != null) navigator.removeRoute(route);
  }
}
