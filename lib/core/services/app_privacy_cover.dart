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
//
// Since stories Wave 3 the app stays mounted (offstage) behind the cover,
// so nothing is disposed when Attune leaves the screen: whatever must stop
// when unseen listens to appContentVisibleProvider.
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderSubscription;
import 'package:attune/core/widgets/keep_mounted_cover.dart';

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

  /// The focused field whose keyboard was hidden when Attune left the
  /// screen, to show again once its content is back (final review I1).
  FocusNode? _keyboardFor;

  /// The app's visibility signal, when there is a ProviderScope above (the
  /// real shell): the keyboard comes back only once the Safety lock's
  /// return check has opened too, never over the checking cover.
  ProviderSubscription<bool>? _visible;

  @override
  void initState() {
    super.initState();
    _visible = listenAppContentVisibleOf(
      context,
      (visible) => visible ? _restoreKeyboard() : _hideKeyboard(),
    );
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        final shouldObscure = _obscuringStates.contains(state);
        // In the lifecycle callback itself: iOS can snapshot before the
        // next frame (see appContentVisibleProvider).
        if (shouldObscure) {
          _hideKeyboard();
        } else if (_visible == null) {
          // No ProviderScope (a bare test): no lock, so resumed is on screen.
          _restoreKeyboard();
        }
        if (shouldObscure != _obscured && mounted) {
          setState(() => _obscured = shouldObscure);
        }
      },
    );
  }

  /// The kept-mounted field keeps its input connection, so the keyboard --
  /// and iOS QuickType's predictions of the draft -- would stay up over the
  /// cover and in the app-switcher snapshot. Before Wave 3 the teardown
  /// closed it. Focus and text are kept; only the keyboard goes down.
  void _hideKeyboard() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || _fieldOf(focus) == null) return;
    // Shown again later only if it was really up (an inset), so a field
    // whose keyboard was already dismissed (Android back) gets none.
    final insets =
        WidgetsBinding.instance.platformDispatcher.implicitView?.viewInsets;
    if (_keyboardFor == null && (insets?.bottom ?? 0) > 0) {
      _keyboardFor = focus;
    }
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  /// Only the same field, still focused: never focus or a keyboard for a
  /// screen that did not have one.
  void _restoreKeyboard() {
    final node = _keyboardFor;
    _keyboardFor = null;
    if (node == null || !mounted) return;
    if (FocusManager.instance.primaryFocus != node || !node.hasFocus) return;
    _fieldOf(node)?.requestKeyboard();
  }

  /// The text field [node] is the focus of, if it is one.
  static EditableTextState? _fieldOf(FocusNode node) {
    final context = node.context;
    if (context == null || !context.mounted) return null;
    return context.findAncestorStateOfType<EditableTextState>();
  }

  @override
  void dispose() {
    _visible?.close();
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Kept mounted, not swapped out (stories Wave 3; 07b G7). Returning the
    // cover *instead of* the child unmounted the Router, so every inactive
    // -- a call, Control Centre, Face ID, a permission alert -- closed the
    // story camera and reel, every sheet and dialog, and reset the chat.
    // Offstage never paints the child, so the OS snapshot and widget
    // finders still see only the neutral cover. See KeepMountedCover.
    return KeepMountedCover(
      obscured: _obscured,
      cover: ColoredBox(
        key: const Key('app_privacy_cover_overlay'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: const _NeutralCoverContent(),
      ),
      child: widget.child,
    );
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
