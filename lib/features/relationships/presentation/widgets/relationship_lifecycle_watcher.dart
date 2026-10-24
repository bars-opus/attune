import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/relationships/domain/relationship_lifecycle.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/widgets/relationship_ended_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spec 3a (research 06 §3 F1 (2), (6); plan review C3): after a pause or an
/// ending, on this phone's next open -- whatever tab it opens on -- the
/// couple's Together surfaces are cleared once, and the person who did not
/// end it sees the warm ending sheet once. Mounted in the app shell, inside
/// the Safety PIN gate; never runs on the quick-exit decoy.
class RelationshipLifecycleWatcher extends ConsumerStatefulWidget {
  const RelationshipLifecycleWatcher({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  static String surfacesClearedKey(String id) =>
      'lifecycle_surfaces_cleared:$id';

  @override
  ConsumerState<RelationshipLifecycleWatcher> createState() =>
      _RelationshipLifecycleWatcherState();
}

class _RelationshipLifecycleWatcherState
    extends ConsumerState<RelationshipLifecycleWatcher> {
  static const _throttle = Duration(minutes: 5);
  DateTime? _last;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  String _path() {
    try {
      return widget.router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return '';
    }
  }

  Future<void> _check({bool force = false}) async {
    if (!mounted || _running) return;
    if (ref.read(lifecycleUserIdProvider) == null) return;
    if (!ref.read(lifecycleLockOpenProvider)) return;
    if (_path() == RouteNames.neutralScreen) return;
    final now = ref.read(lifecycleClockProvider)();
    if (!force && _last != null && now.difference(_last!) < _throttle) return;
    _last = now;
    _running = true;
    try {
      final l =
          await ref.read(relationshipLifecycleServiceProvider).fetchLifecycle();
      if (l == null || !mounted) return;
      await _clearOnce(l);
      if (!mounted || _path() == RouteNames.neutralScreen) return;
      final navContext =
          widget.router.routerDelegate.navigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        await RelationshipEndedSheet.maybeShow(navContext, l);
      }
    } catch (_) {
      // A failed read changes nothing; the next open tries again.
    } finally {
      _running = false;
    }
  }

  Future<void> _clearOnce(RelationshipLifecycle l) async {
    final prefs = await SharedPreferences.getInstance();
        // Per state, not per relationship: after a pause, a resume and then an
    // ending, the couple's surfaces may be back and must go again (IMP-1).
    final key = RelationshipLifecycleWatcher.surfacesClearedKey(
      '${l.relationshipId}:${l.status.name}',
    );
    if (prefs.getBool(key) ?? false) return;
    try {
      await ref.read(lifecycleClearSurfacesProvider)();
    } catch (_) {}
    await prefs.setBool(key, true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(lifecycleLockOpenProvider, (prev, next) {
      // Every return from the background passes the lock check (checking
      // -> open). The shell keeps this widget mounted across it now
      // (stories Wave 3), so this is "the next open": ask again, as the
      // fresh mount on every return used to.
      if (next && prev == false) _check(force: true);
    });
    ref.listen<String?>(lifecycleUserIdProvider, (prev, next) {
      if (next != null && next != prev) _check(force: true);
    });
    return widget.child;
  }
}
