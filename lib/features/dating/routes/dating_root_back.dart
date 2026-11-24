// Spec 2 W6a fix round 1 (I-3): a Dating page that is the only page (the
// Dating lock's return goes back to it with go(), and a link opens it on
// its own) still has a way back. Its route names where back leads: a chat
// to Conversations; Conversations, Today and Dating settings to Me. Pushed
// over another page, nothing changes (the AppBar's own back and the
// system back pop as before). The lock's routing is untouched.
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/home/home_location.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Me: where a Dating page that is the only page goes back to.
String datingMeLocation() => homeLocation(tab: AppTab.me);

/// Final client fix (M-1): "only page" is read from the router's pages,
/// never the navigator's routes: a sheet or a picker open over the page is
/// a route too, and the back must not go while one is open (nothing would
/// bring it back when the sheet is dismissed).
bool _onlyPage(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  return router != null &&
      router.routerDelegate.currentConfiguration.matches.length <= 1;
}

/// Wraps a Dating route's page: when it is the only page, the system back
/// goes to [to] (never out of the app), and [datingRootBackButton] shows.
/// Spec 2 W9 final client fix (M-1, M-3): not while a [DatingOwnBack] below
/// answers the back itself (a route's every pop handler runs, so the two
/// would both go).
class DatingRootBack extends StatefulWidget {
  const DatingRootBack({super.key, required this.to, required this.child});

  final String Function() to;
  final Widget child;

  @override
  State<DatingRootBack> createState() => _DatingRootBackState();
}

class _DatingRootBackState extends State<DatingRootBack> {
  /// The [DatingOwnBack]s below that answer the back now.
  final _owners = <Object>{};

  // One shape whether or not it is the only page (a page pushed on top
  // rebuilds this one; a changed shape would make its screen anew).
  @override
  Widget build(BuildContext context) {
    final only = _onlyPage(context);
    return PopScope(
      canPop: !only,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _owners.isEmpty && _onlyPage(context)) {
          context.go(widget.to());
        }
      },
      child: _DatingRootBackScope(
        to: widget.to,
        owners: _owners,
        child: widget.child,
      ),
    );
  }
}

/// Spec 2 W9 final client fix (M-1, M-3): while [active], the system back
/// on this page is [onBack]'s alone: the route doesn't pop, and the
/// [DatingRootBack] above (if any) doesn't go to its fallback too. Not
/// active, it changes nothing.
class DatingOwnBack extends StatefulWidget {
  const DatingOwnBack({
    super.key,
    required this.active,
    required this.onBack,
    required this.child,
  });

  final bool active;
  final VoidCallback onBack;
  final Widget child;

  @override
  State<DatingOwnBack> createState() => _DatingOwnBackState();
}

class _DatingOwnBackState extends State<DatingOwnBack> {
  Set<Object>? _owners;

  void _sync() {
    if (widget.active) {
      _owners?.add(this);
    } else {
      _owners?.remove(this);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owners =
        context.getInheritedWidgetOfExactType<_DatingRootBackScope>()?.owners;
    if (!identical(owners, _owners)) {
      _owners?.remove(this);
      _owners = owners;
    }
    _sync();
  }

  @override
  void didUpdateWidget(DatingOwnBack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _owners?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.active,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && widget.active) widget.onBack();
    },
    child: widget.child,
  );
}

class _DatingRootBackScope extends InheritedWidget {
  const _DatingRootBackScope({
    required this.to,
    required this.owners,
    required super.child,
  });

  final String Function() to;
  final Set<Object> owners;

  @override
  bool updateShouldNotify(_DatingRootBackScope old) => false;
}

/// An AppBar's leading on a Dating page: a back button to its route's
/// fallback when the page is the only page; otherwise null (the AppBar's
/// own back shows when there is a page to go back to).
Widget? datingRootBackButton(BuildContext context) {
  final scope = context.getInheritedWidgetOfExactType<_DatingRootBackScope>();
  if (scope == null || !_onlyPage(context)) return null;
  return BackButton(
    key: const ValueKey('dating_root_back'),
    onPressed: () => context.go(scope.to()),
  );
}
