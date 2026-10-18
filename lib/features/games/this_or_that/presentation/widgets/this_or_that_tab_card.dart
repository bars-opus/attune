import 'package:attune/core/ui/motion/reduce_motion.dart';
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

/// A question and its two answers as three layered tabs, like a set of
/// folder dividers.
///
/// The round opens on the middle tab with the question. Pulling the left
/// or right tab forward floods the whole card with that option's colour
/// and IS the answer -- there is no separate confirm, because the colour
/// arriving is a better confirmation than a button could be.
///
/// Two side-by-side cards (what this replaces) make the player compare
/// two small things. One card that BECOMES the choice makes the choice
/// feel like a commitment, which is what a question about your partner
/// should feel like.
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
    final reduceMotion = reduceMotionOf(context);

    final surface = switch (active) {
      ThisOrThatTab.thisOption => palette.thisColor,
      ThisOrThatTab.thatOption => palette.thatColor,
      ThisOrThatTab.question => palette.panel,
    };

    // Text has to stay legible on three different grounds, and the two
    // option colours are saturated while the question panel is not.
    final onSurface =
        active == ThisOrThatTab.question
            ? palette.ink
            : ThemeData.estimateBrightnessForColor(surface) == Brightness.dark
            ? Colors.white
            : palette.ink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _Tab(
                label: 'THIS',
                color: palette.thisColor,
                forward: active == ThisOrThatTab.thisOption,
                reduceMotion: reduceMotion,
                onTap:
                    onSelect == null
                        ? null
                        : () => onSelect!(ThisOrThatTab.thisOption),
              ),
            ),
            Expanded(
              child: _Tab(
                label: 'OR',
                color: palette.panel,
                labelColor: palette.mutedInk,
                forward: active == ThisOrThatTab.question,
                reduceMotion: reduceMotion,
                // The middle tab is not a choice -- it is where the
                // round starts. Making it tappable would offer a way to
                // un-answer, and an answer you can take back is not the
                // commitment this game is asking for.
                onTap: null,
              ),
            ),
            Expanded(
              child: _Tab(
                label: 'THAT',
                color: palette.thatColor,
                forward: active == ThisOrThatTab.thatOption,
                reduceMotion: reduceMotion,
                onTap:
                    onSelect == null
                        ? null
                        : () => onSelect!(ThisOrThatTab.thatOption),
              ),
            ),
          ],
        ),
        AnimatedContainer(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22),
              bottomRight: Radius.circular(22),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
          child: _CardBody(
            active: active,
            questionText: questionText,
            optionA: optionA,
            optionB: optionB,
            emojiA: emojiA,
            emojiB: emojiB,
            onSurface: onSurface,
            reduceMotion: reduceMotion,
          ),
        ),
      ],
    );
  }
}

/// One divider tab.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.color,
    required this.forward,
    required this.reduceMotion,
    this.labelColor,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool forward;
  final bool reduceMotion;
  final Color? labelColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final ink =
        labelColor ??
        (ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : palette.ink);

    return Semantics(
      button: onTap != null,
      selected: forward,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          // A tab that is forward sits taller and loses the gap beneath
          // it, so it reads as joined to the card rather than resting on
          // it. That join is the whole illusion.
          height: forward ? 46 : 38,
          margin: EdgeInsets.only(
            bottom: forward ? 0 : 8,
            right: 2,
            left: 2,
          ),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          alignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration:
                reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
            style: TextStyle(
              color: ink.withValues(alpha: forward ? 1 : 0.62),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
            child: Text(label),
          ),
        ),
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
    required this.onSurface,
    required this.reduceMotion,
    this.emojiA,
    this.emojiB,
  });

  final ThisOrThatTab active;
  final String questionText;
  final String optionA;
  final String optionB;
  final Color onSurface;
  final bool reduceMotion;
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
    // throws. The enclosing AnimatedContainer already animates the
    // card's height, so the resize is carried there instead.
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The question stays visible after a choice, smaller. Removing
          // it would leave the answer with nothing to be an answer TO,
          // and a partner glancing over should still see what was asked.
          AnimatedDefaultTextStyle(
            duration:
                reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: onSurface.withValues(
                alpha: chosen == null ? 1 : 0.72,
              ),
              fontSize: chosen == null ? 30 : 17,
              height: 1.12,
              fontWeight: chosen == null ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: -0.4,
            ),
            child: Text(questionText),
          ),
          if (chosen != null) ...[
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (emoji != null && emoji.isNotEmpty) ...[
                  Text(emoji, style: const TextStyle(fontSize: 34)),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    chosen,
                    style: TextStyle(
                      color: onSurface,
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
