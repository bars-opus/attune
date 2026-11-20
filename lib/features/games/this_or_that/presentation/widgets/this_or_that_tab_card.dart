import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';

/// Which of the three tabs is forward.
enum ThisOrThatTab {
  /// Option A. Left tab, warm.
  thisOption,

  /// The question. Middle tab, and where a round starts.
  question,

  /// Option B. Right tab, cool.
  thatOption,
}

/// Marks the row of tabs of the [ThisOrThatTabCard] below it with
/// [target], so a tutorial can point at the tabs rather than the whole card.
class ThisOrThatTabRowTarget extends InheritedWidget {
  const ThisOrThatTabRowTarget({
    super.key,
    required this.target,
    required super.child,
  });

  final GlobalKey target;

  static GlobalKey? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ThisOrThatTabRowTarget>()
          ?.target;

  @override
  bool updateShouldNotify(ThisOrThatTabRowTarget oldWidget) =>
      oldWidget.target != target;
}

/// A question and its two answers: three tabs over one card.
///
/// The round opens on the middle tab with the question. Pulling the left
/// or right tab forward floods the whole card with that option's colour
/// and IS the answer -- there is no separate confirm, because the colour
/// arriving is a better confirmation than a button could be.
///
/// Two side-by-side cards (what this replaced) make the player compare
/// two small things. One card that BECOMES the choice makes the choice
/// feel like a commitment, which is what a question about your partner
/// should feel like.
///
/// Everything is the games' tile: flat faces over hard offset shadows. The
/// forward tab stands on a deeper shadow and shares the card's colour, so
/// which tab the card belongs to reads without reading a word.
class ThisOrThatTabCard extends StatelessWidget {
  const ThisOrThatTabCard({
    super.key,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    required this.active,
    this.emojiA,
    this.emojiB,
    this.onSelect,
  });

  final String questionText;
  final String optionA;
  final String optionB;

  /// Which tab is forward. [ThisOrThatTab.question] until a choice.
  final ThisOrThatTab active;

  final String? emojiA;
  final String? emojiB;

  /// Null while submitting, so a committed answer cannot be changed
  /// mid-flight.
  final ValueChanged<ThisOrThatTab>? onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);

    final surface = switch (active) {
      ThisOrThatTab.thisOption => palette.thisColor,
      ThisOrThatTab.thatOption => palette.thatColor,
      ThisOrThatTab.question => GameTheme.tile,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          key: ThisOrThatTabRowTarget.maybeOf(context),
          // Bottoms aligned: a tab further back sits on a shallower
          // shadow, so its face is lower -- pressed in, next to the one
          // standing up.
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _Tab(
                label: 'THIS',
                face: palette.thisColor,
                forward: active == ThisOrThatTab.thisOption,
                onTap:
                    onSelect == null
                        ? null
                        : () => onSelect!(ThisOrThatTab.thisOption),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tab(
                label: 'OR',
                face: GameTheme.tile,
                forward: active == ThisOrThatTab.question,
                // The middle tab is not a choice -- it is where the
                // round starts. Making it tappable would offer a way to
                // un-answer, and an answer you can take back is not the
                // commitment this game is asking for.
                onTap: null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tab(
                label: 'THAT',
                face: palette.thatColor,
                forward: active == ThisOrThatTab.thatOption,
                onTap:
                    onSelect == null
                        ? null
                        : () => onSelect!(ThisOrThatTab.thatOption),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _Panel(
          color: surface,
          child: _CardBody(
            active: active,
            questionText: questionText,
            optionA: optionA,
            optionB: optionB,
            emojiA: emojiA,
            emojiB: emojiB,
            ink: _inkOn(surface),
          ),
        ),
      ],
    );
  }
}

/// WCAG contrast between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// White or the tile's ink, whichever reads better on [face].
Color _inkOn(Color face) =>
    _contrast(Colors.white, face) > _contrast(GameTheme.tileInk, face)
        ? Colors.white
        : GameTheme.tileInk;

/// [ink] mixed toward [face] for a tab that is not forward: 62% strength
/// where that still reads, and only as faint as 4.5:1 allows where it does
/// not. On the two option colours 62% would fall to about 3.8:1.
Color _dimmed(Color ink, Color face) {
  // A hair over the bar, so rounding in the mix cannot land under it.
  const bar = 4.6;
  for (var strength = 0.62; strength < 1; strength += 0.02) {
    final mixed = Color.lerp(face, ink, strength)!;
    if (_contrast(mixed, face) >= bar) return mixed;
  }
  return ink;
}

/// One tab: a tile in its option's colour.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.face,
    required this.forward,
    this.onTap,
  });

  final String label;
  final Color face;
  final bool forward;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = _inkOn(face);

    return GameTile(
      color: face,
      radius: 14,
      depth: forward ? 5 : 2,
      semanticLabel: label,
      selected: forward,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: GameMotion.of(context, GameMotion.settle),
          curve: GameMotion.enterCurve,
          // Merged, not replaced: a bare style here would drop the app's
          // font for the platform's default.
          style: DefaultTextStyle.of(context).style.merge(
            TextStyle(
              color: forward ? ink : _dimmed(ink, face),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          child: Text(label, maxLines: 1),
        ),
      ),
    );
  }
}

/// The card itself: one tile-shaped panel whose colour is the choice.
///
/// Drawn here rather than as a [GameTile] because its colour change is the
/// answer arriving, and runs at the settle pace rather than a press's.
class _Panel extends StatelessWidget {
  const _Panel({required this.color, required this.child});

  final Color color;
  final Widget child;

  static const double _depth = 6;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(22));

  @override
  Widget build(BuildContext context) {
    const dx = _depth * GameTile.lean;

    // The padding reserves the shadow's room, as a tile's does.
    return Padding(
      padding: const EdgeInsets.only(right: dx, bottom: _depth),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Transform.translate(
              offset: const Offset(dx, _depth),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: GameTheme.tileShadow,
                  borderRadius: _radius,
                ),
              ),
            ),
          ),
          AnimatedContainer(
            key: const ValueKey('this-or-that-card-panel'),
            duration: GameMotion.of(context, GameMotion.settle),
            curve: GameMotion.enterCurve,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
            decoration: BoxDecoration(color: color, borderRadius: _radius),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// What the card says, which depends on which tab is forward.
class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.active,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    required this.ink,
    this.emojiA,
    this.emojiB,
  });

  final ThisOrThatTab active;
  final String questionText;
  final String optionA;
  final String optionB;
  final Color ink;
  final String? emojiA;
  final String? emojiB;

  @override
  Widget build(BuildContext context) {
    final chosen = switch (active) {
      ThisOrThatTab.thisOption => optionA,
      ThisOrThatTab.thatOption => optionB,
      ThisOrThatTab.question => null,
    };
    final emoji = switch (active) {
      ThisOrThatTab.thisOption => emojiA,
      ThisOrThatTab.thatOption => emojiB,
      ThisOrThatTab.question => null,
    };

    // No AnimatedSize here. It wraps children that animate their OWN
    // size -- AnimatedDefaultTextStyle changes the question's font size
    // -- and a RenderAnimatedSize mutated during its own performLayout
    // throws. The enclosing AnimatedContainer carries the resize instead.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The question stays visible after a choice, smaller. Removing
        // it would leave the answer with nothing to be an answer TO,
        // and a partner glancing over should still see what was asked.
        AnimatedDefaultTextStyle(
          duration: GameMotion.of(context, GameMotion.settle),
          curve: GameMotion.enterCurve,
          style: DefaultTextStyle.of(context).style.merge(
            TextStyle(
              color: ink,
              fontSize: chosen == null ? 30 : 17,
              height: 1.12,
              fontWeight: chosen == null ? FontWeight.w800 : FontWeight.w700,
              letterSpacing: chosen == null ? -0.4 : 0,
            ),
          ),
          child: Text(questionText),
        ),
        if (chosen != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              if (emoji != null && emoji.isNotEmpty) ...[
                Text(emoji, style: TextStyle(color: ink, fontSize: 34)),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  chosen,
                  style: TextStyle(
                    color: ink,
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
