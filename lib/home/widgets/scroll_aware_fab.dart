import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps a screen's FloatingActionButton so it mirrors the shell's bottom
/// nav bar: hidden while the nav is visible (idle / scrolling up), shown
/// while the nav is hidden (scrolling down) — see nav_visibility_provider.dart.
class ScrollAwareFab extends ConsumerWidget {
  const ScrollAwareFab({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navVisible = ref.watch(navVisibilityProvider);
    final fabVisible = !navVisible;

    return IgnorePointer(
      ignoring: !fabVisible,
      child: AnimatedSlide(
        duration: AnimationDurations.fast,
        curve: Curves.easeOut,
        offset: fabVisible ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: AnimationDurations.fast,
          opacity: fabVisible ? 1 : 0,
          child: child,
        ),
      ),
    );
  }
}
