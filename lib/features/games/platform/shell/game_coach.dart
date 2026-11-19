import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One thing the tutorial says, and optionally the thing it points at.
@immutable
class GameCoachStep {
  const GameCoachStep({required this.text, this.target});

  final String text;

  /// The widget to ring and point at. Null shows the bubble alone.
  final GlobalKey? target;
}

/// Remembers, per device, which games' tutorials have been seen.
class GameCoachStore {
  GameCoachStore(this._prefs);

  final SharedPreferences _prefs;

  static String key(String gameType) => 'games.coach.seen.$gameType';

  bool seen(String gameType) => _prefs.getBool(key(gameType)) ?? false;

  Future<void> markSeen(String gameType) => _prefs.setBool(key(gameType), true);
}

final gameCoachStoreProvider = Provider<GameCoachStore>(
  (ref) => GameCoachStore(ref.watch(sharedPreferencesProvider)),
);

/// The tutorial's speech bubble.
class GameCoachBubble extends StatelessWidget {
  const GameCoachBubble({
    super.key,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.onSkip,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  /// Null hides Skip, on the last step.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: GameTheme.raised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: GameTheme.onGround, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The words give way when space is short; the buttons under
          // them never do. A long step at a large text size on a small
          // phone is taller than the screen, and a tutorial whose Next and
          // Skip have run off the bottom cannot be got out of.
          Flexible(
            child: SingleChildScrollView(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  text,
                  style: const TextStyle(
                    color: GameTheme.onGround,
                    fontSize: 16,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GamePrimaryButton(label: actionLabel, onTap: onAction),
          if (onSkip != null) ...[
            const SizedBox(height: 8),
            Semantics(
              button: true,
              label: GameStrings.skip,
              container: true,
              excludeSemantics: true,
              onTap: onSkip,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSkip,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    GameStrings.skip,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: GameTheme.mutedOnGround,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Walks a first-time player through a game, over the game itself.
///
/// Wrap the game's body with it, not the whole screen: the bubble sits at
/// the top of whatever it wraps, and around the body that is under the
/// header rather than on top of the back button.
///
/// It shows once per game per device and can be skipped at any step. The
/// game underneath stays live: the ring around a target does not take
/// touches, so the player can do the thing being described.
///
/// [force] replays it for someone who asked, whatever the store says.
class GameCoach extends ConsumerStatefulWidget {
  const GameCoach({
    super.key,
    required this.gameType,
    required this.steps,
    required this.child,
    this.force = false,
    this.replay = 0,
    this.onDone,
  });

  final String gameType;
  final List<GameCoachStep> steps;
  final Widget child;
  final bool force;

  /// Raise it to show the tutorial again from step one, seen or not -- for
  /// a "show me how to play" in a settings sheet. The stored flag is
  /// neither read nor cleared; finishing the replay leaves it set.
  final int replay;

  final VoidCallback? onDone;

  @override
  ConsumerState<GameCoach> createState() => _GameCoachState();
}

class _GameCoachState extends ConsumerState<GameCoach> {
  final GlobalKey _stackKey = GlobalKey();

  /// The step showing, or null when the tutorial is not running.
  int? _index;
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    final seen = ref.read(gameCoachStoreProvider).seen(widget.gameType);
    if (widget.steps.isNotEmpty && (widget.force || !seen)) {
      _index = 0;
      _watchTarget();
    }
  }

  @override
  void didUpdateWidget(GameCoach oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.replay > oldWidget.replay && widget.steps.isNotEmpty) {
      _index = 0;
      _targetRect = null;
      _watchTarget();
    }
  }

  /// The step showing, kept inside the list: a rebuild can hand over fewer
  /// steps than there were.
  int? get _step {
    final index = _index;
    if (index == null || widget.steps.isEmpty) return null;
    return index < widget.steps.length ? index : widget.steps.length - 1;
  }

  bool _watching = false;

  /// Re-measures the target after every frame for as long as the tutorial
  /// is showing.
  ///
  /// The target can move without this widget rebuilding: the game scrolls,
  /// the phone turns, a keyboard opens. Each of those draws a frame, and a
  /// callback registered from inside a post-frame callback runs after the
  /// next frame without asking for one -- so this follows the target
  /// wherever it goes and costs nothing while the screen is still.
  void _watchTarget() {
    if (_watching) return;
    _watching = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _watching = false;
      if (!mounted || _step == null) return;
      _measure();
      _watchTarget();
    });
  }

  void _advance() {
    final index = _step;
    if (index == null) return;
    if (index >= widget.steps.length - 1) {
      _finish();
    } else {
      setState(() {
        _index = index + 1;
        _targetRect = null;
      });
    }
  }

  void _finish() {
    unawaited(ref.read(gameCoachStoreProvider).markSeen(widget.gameType));
    setState(() {
      _index = null;
      _targetRect = null;
    });
    widget.onDone?.call();
  }

  /// Finds the current target on screen, in this widget's own coordinates.
  ///
  /// Runs after layout, because a target's position does not exist until
  /// then. It only rebuilds when the answer changed, so measuring after
  /// every frame cannot loop.
  void _measure() {
    final index = _step;
    if (!mounted || index == null) return;

    final target =
        widget.steps[index].target?.currentContext?.findRenderObject();
    final stack = _stackKey.currentContext?.findRenderObject();
    Rect? rect;
    if (target is RenderBox &&
        stack is RenderBox &&
        target.attached &&
        target.hasSize) {
      // Through screen coordinates, so the target does not have to be
      // inside this widget: a tutorial around the board can still point
      // at a button in the bar under it.
      final topLeft =
          target.localToGlobal(Offset.zero) - stack.localToGlobal(Offset.zero);
      rect = topLeft & target.size;
    }
    if (rect != _targetRect) setState(() => _targetRect = rect);
  }

  @override
  Widget build(BuildContext context) {
    final index = _step;
    final rect = _targetRect;
    final isLast = index != null && index >= widget.steps.length - 1;

    return Stack(
      key: _stackKey,
      // The ring may sit over something outside this widget.
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (index != null && rect != null)
          Positioned.fromRect(
            rect: rect.inflate(5),
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('game-coach-ring'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: GameTheme.onGround, width: 3),
                ),
              ),
            ),
          ),
        if (index != null && rect != null)
          Positioned(
            left: rect.right - 18,
            top: rect.bottom - 18,
            child: const IgnorePointer(
              child: Icon(
                Icons.touch_app_rounded,
                color: GameTheme.onGround,
                size: 36,
              ),
            ),
          ),
        if (index != null)
          // Bounded top and bottom so the bubble can never be taller than
          // the space it has; aligned to the top so it is only as tall as
          // it needs. The Align takes no touches of its own, so the game
          // under the rest of this area stays live.
          Positioned(
            left: 16,
            right: 16,
            top: 8,
            bottom: 8,
            child: Align(
              alignment: Alignment.topCenter,
              child: GameCoachBubble(
                text: widget.steps[index].text,
                actionLabel: isLast ? GameStrings.gotIt : GameStrings.next,
                onAction: _advance,
                onSkip: isLast ? null : _finish,
              ),
            ),
          ),
      ],
    );
  }
}
