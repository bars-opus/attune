import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/triple_tap_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The one quick-exit target (Spec 2; research 06 §3 F3 (1)), in the root
/// shell above the Navigator, so it covers every route, dialog and sheet.
/// Always mounted (so the Router below is never reparented on sign-in),
/// enabled only while signed in. The builder's context is above the Router,
/// so it drives the router directly.
class QuickExitZone extends ConsumerWidget {
  const QuickExitZone({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TripleTapDetector(
      enabled: ref.watch(currentUserProvider) != null,
      onTripleTap: () => QuickExitService.executeWithRouter(router),
      child: child,
    );
  }
}
