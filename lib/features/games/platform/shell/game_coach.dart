import 'dart:async';
import 'dart:math' as math;

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
          // Skip and the action share one row, so the bubble is as short
          // as it can be: on a small phone every line it saves is game the
          // player can still see and touch. Where the two do not fit side
          // by side -- the largest text on the smallest phone -- the action
          // goes on top and Skip under it, rather than either being cut.
          OverflowBar(
            alignment:
                onSkip == null
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.spaceBetween,
            spacing: 16,
            overflowSpacing: 4,
            overflowAlignment: OverflowBarAlignment.center,
            overflowDirection: VerticalDirection.up,
            children: [
              if (onSkip != null)
                Semantics(
                  button: true,
                  label: GameStrings.skip,
                  container: true,
                  excludeSemantics: true,
                  onTap: onSkip,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSkip,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 44,
                        minWidth: 44,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: 1,
                          heightFactor: 1,
                          child: Text(
                            GameStrings.skip,
                            style: TextStyle(
                              color: GameTheme.mutedOnGround,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              _CoachAction(label: actionLabel, onTap: onAction),
            ],
          ),
        ],
      ),
    );
  }
}

/// The bubble's own action: a compact white pill, Next or Got it.
///
/// Not a [GamePrimaryButton]: that pill fills the width it is given and is
/// 56 high, and here it shares a row with Skip.
class _CoachAction extends StatelessWidget {
  const _CoachAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      container: true,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            color: GameTheme.tile,
            borderRadius: BorderRadius.circular(999),
          ),
          // As wide as its word, centred in the 44 px it is given.
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: GameTheme.tileInk,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
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

  /// The step whose target has been looked for. Until the step showing has
  /// been, a step with a target draws no bubble: the bubble's side depends
  /// on where the target is, and drawing it before that is known puts it,
  /// for a frame, somewhere it is about to leave -- often on the target.
  int? _measuredStep;

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
      // The game under the tutorial is already laid out, so the first
      // step's target can be found now, for this frame.
      _targetRect = _find(0);
      _measuredStep = 0;
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
      // The next target is already on screen and laid out: found now,
      // the bubble is drawn where it belongs on the step's first frame.
      final rect = _find(index + 1);
      setState(() {
        _index = index + 1;
        _targetRect = rect;
        _measuredStep = index + 1;
      });
    }
  }

  void _finish() {
    unawaited(ref.read(gameCoachStoreProvider).markSeen(widget.gameType));
    setState(() {
      _index = null;
      _targetRect = null;
      _measuredStep = null;
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

    final rect = _find(index);
    if (rect != _targetRect || _measuredStep != index) {
      setState(() {
        _targetRect = rect;
        _measuredStep = index;
      });
    }
  }

  /// Where step [index]'s target is, in this widget's coordinates, from the
  /// last layout; null when it has none or it is not on screen.
  Rect? _find(int index) {
    if (index >= widget.steps.length) return null;
    final target =
        widget.steps[index].target?.currentContext?.findRenderObject();
    final stack = _stackKey.currentContext?.findRenderObject();
    if (target is! RenderBox ||
        stack is! RenderBox ||
        !target.attached ||
        !stack.attached ||
        !target.hasSize ||
        !stack.hasSize) {
      return null;
    }
    // Through screen coordinates, so the target does not have to be
    // inside this widget: a tutorial around the board can still point at
    // a button in the bar under it.
    final topLeft =
        target.localToGlobal(Offset.zero) - stack.localToGlobal(Offset.zero);
    return topLeft & target.size;
  }

  @override
  Widget build(BuildContext context) {
    final index = _step;
    final rect = _targetRect;
    final isLast = index != null && index >= widget.steps.length - 1;
    // A step that points at nothing is drawn at once; one that points at
    // something waits until its target has been looked for. A target that
    // cannot be found does not hold the bubble back for longer than that.
    final placed =
        index != null &&
        (widget.steps[index].target == null || _measuredStep == index);

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
        if (placed)
          // Never taller than the space it has, and only as tall as it
          // needs; on whichever side leaves the target free. The layout
          // takes no touches of its own, so the game under the rest of
          // this area stays live.
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _BubblePlacement(rect),
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

/// Puts the bubble where it does not cover what it points at.
///
/// A tutorial that says "tap this" over the thing to tap cannot be
/// followed. So the bubble goes to the far side of its area from the
/// target -- the bottom for a target in the upper part, the top for one in
/// the lower part -- and to the other side if that is the one that misses
/// the target. Where neither misses it, the side that leaves the target's
/// middle free to tap wins, then the side covering less of it.
///
/// A target outside the area cannot be covered from either side; the
/// bubble sits on the side nearest it, which reads as pointing at it and
/// leaves the rest of the area -- the game -- clear. A step that points at
/// nothing keeps the bubble at the top.
class _BubblePlacement extends SingleChildLayoutDelegate {
  _BubblePlacement(this.target);

  /// The target, in the area's coordinates. Null when there is none, or
  /// before it has been measured.
  final Rect? target;

  static const double _margin = 8;
  static const double _inset = 16;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.max(0.0, constraints.maxWidth - _inset * 2);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(0.0, constraints.maxHeight - _margin * 2),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const top = Offset(_inset, _margin);
    final bottom = Offset(
      _inset,
      math.max(_margin, size.height - _margin - childSize.height),
    );
    final target = this.target;
    if (target == null) return top;
    if (target.top >= size.height) return bottom;
    if (target.bottom <= 0) return top;

    // The ring is part of what must stay visible.
    final ringed = target.inflate(5);
    final sides =
        target.center.dy < size.height / 2 ? [bottom, top] : [top, bottom];
    double covered(Offset at) {
      final overlap = (at & childSize).intersect(ringed);
      return overlap.isEmpty ? 0 : overlap.width * overlap.height;
    }

    for (final at in sides) {
      if (covered(at) == 0) return at;
    }
    final centreFree = [
      for (final at in sides)
        if (!(at & childSize).contains(target.center)) at,
    ];
    final candidates = centreFree.isEmpty ? sides : centreFree;
    return candidates.reduce((a, b) => covered(b) < covered(a) ? b : a);
  }

  @override
  bool shouldRelayout(_BubblePlacement oldDelegate) =>
      oldDelegate.target != target;
}
