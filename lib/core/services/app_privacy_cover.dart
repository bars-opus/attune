// A global, always-on cover that obscures every screen the instant the
// app leaves the foreground -- inactive (an incoming call, the app
// switcher, a system dialog), paused, or hidden. This closes the gap the
// AI Assistant spec's §6.3/§14.1 identified: this app previously had
// only Quick Exit's manually-triggered neutral route
// (lib/features/safety/domain/services/quick_exit_service.dart), never
// an automatic cover for an ordinary platform snapshot (the app-switcher
// thumbnail, a screenshot taken while backgrounding). Understand mode's
// private interpretation may rely on this only because it is wired in
// globally here, not per-screen.
//
// Uses AppLifecycleListener (not a WidgetsBindingObserver mixin), the
// same choice story_providers.dart and planning_providers.dart already
// made for their own lifecycle-driven logic in this codebase.
import 'package:flutter/material.dart';

class AppPrivacyCover extends StatefulWidget {
  const AppPrivacyCover({super.key, required this.child});

  final Widget child;

  @override
  State<AppPrivacyCover> createState() => _AppPrivacyCoverState();
}

class _AppPrivacyCoverState extends State<AppPrivacyCover> {
  late final AppLifecycleListener _lifecycleListener;
  bool _obscured = false;

  static const _obscuringStates = {
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
  };

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        final shouldObscure = _obscuringStates.contains(state);
        if (shouldObscure != _obscured && mounted) {
          setState(() => _obscured = shouldObscure);
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When obscured, the real child is not merely painted behind the
    // cover -- it is removed from the tree entirely. A Stack that keeps
    // the child underneath would still let widget/semantics finders (and
    // some platform screenshot paths) see the "secret" content; swapping
    // it out is what actually guarantees the OS snapshot -- and anything
    // else inspecting the tree -- sees only the neutral cover.
    if (_obscured) {
      return ColoredBox(
        key: const Key('app_privacy_cover_overlay'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: const _NeutralCoverContent(),
      );
    }
    return widget.child;
  }
}

class _NeutralCoverContent extends StatelessWidget {
  const _NeutralCoverContent();

  @override
  Widget build(BuildContext context) {
    // Deliberately minimal: the app's own icon/name only, nothing that
    // could itself leak information about what was on screen a moment
    // ago. No message text, no partner name, no screen-specific state.
    return const Center(
      child: Icon(Icons.favorite, size: 48),
    );
  }
}
