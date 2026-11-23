// Spec 2 W3 final fix (I-1b): the Dating sheets and dialogs that can open
// over Me carry a route name under one prefix, and each one is tracked
// while it is open. When the Dating unlock ends with the lock on, only
// these are removed, wherever they sit in the stack: a Spec 1 sheet on Me
// (Quizzes, Healing, the journal reminder, More ways) stays, with what was
// typed in it, even one opened over a Dating sheet.
//
// Spec 2 W8a fix round 1 (I-1): each one is blank once quick exit or
// sign-out runs (DatingSurfaceGuard), in the decoy's first frame.
import 'package:attune/features/dating/device/dating_surface.dart';
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
  Widget build(BuildContext context) => DatingSurfaceGuard(child: widget.child);
}

/// Spec 2 W8a round 2 (Re-1-M2): no Dating sheet, dialog or picker opens
/// once quick exit or sign-out has run, until Dating shows again; each
/// opener answers as if dismissed (DatingSurfaceGuard's hold is the
/// backstop).
bool get datingSheetRefused => DatingSurface.hidden.value;

/// Removes every open Dating sheet (and only those). A sheet above one
/// stays where it is; nothing of the Dating sheet is left to read.
void closeDatingSheets() {
  for (final route in List.of(_open)) {
    _open.remove(route);
    final navigator = route.navigator;
    if (route.isActive && navigator != null) navigator.removeRoute(route);
  }
}
