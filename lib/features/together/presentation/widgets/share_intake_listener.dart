import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline_providers;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/shared_capture.dart';
import '../together_providers.dart';

/// Brings Together forward for a share, except over quick exit's neutral
/// screen: there the share waits, and lapses after 10 minutes (Phase 8b R6).
void showTogetherForShare(GoRouter router) {
  final path = router.routerDelegate.currentConfiguration.uri.path;
  if (path == RouteNames.neutralScreen) return;
  router.go(RouteNames.together);
}

/// Turns a share from another app into a pending note and asks the app to
/// show Together (Phase 8b). Nothing is saved; nothing calls the AI.
class ShareIntakeListener extends ConsumerStatefulWidget {
  const ShareIntakeListener({
    super.key,
    required this.child,
    required this.onShare,
  });
  final Widget child;
  final void Function() onShare;

  @override
  ConsumerState<ShareIntakeListener> createState() =>
      _ShareIntakeListenerState();
}

class _ShareIntakeListenerState extends ConsumerState<ShareIntakeListener> {
  StreamSubscription<List<SharedItem>>? _sub;

  @override
  void initState() {
    super.initState();
    final source = ref.read(shareSourceProvider);
    _sub = source.stream().listen(_take, onError: (_) {});
    source.initial().then(_take).catchError((_) {});
  }

  Future<void> _take(List<SharedItem> items) async {
    final text = sharedCaptureText(items);
    if (text == null || !mounted) return;
    ref.read(pendingShareProvider.notifier).state = PendingShare(
      text,
      DateTime.now(),
    );
    ref.read(shareSourceProvider).reset().catchError((_) {});
    // Only a signed-in, paired person is taken to Together; anyone else
    // keeps their place (login, onboarding) and the share waits (R6).
    String? relationshipId;
    try {
      relationshipId = await ref.read(
        timeline_providers.currentRelationshipIdProvider.future,
      );
    } catch (_) {}
    if (relationshipId == null || !mounted) return;
    widget.onShare();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
