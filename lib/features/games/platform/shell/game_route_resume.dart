import 'package:flutter/widgets.dart';

/// Tells a page when its route is in front again after something covered
/// it: a game, a landing page, a sheet.
///
/// [onRouteResumed] runs after the frame in which that happened, never
/// during it: re-reading usually invalidates or writes a provider, which
/// throws while the tree is building.
mixin GameRouteResume<T extends StatefulWidget> on State<T> {
  /// Whether this page's route was in front at the last look. Null before
  /// the first.
  bool? _wasCurrent;

  /// The page is in front again. Called after the frame, while mounted.
  void onRouteResumed();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depends on the route's isCurrent alone, so this runs again exactly
    // when something covers the page or stops covering it.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && _wasCurrent == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onRouteResumed();
      });
    }
    _wasCurrent = current;
  }
}
