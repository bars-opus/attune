import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:flutter/material.dart';

/// A word spelled in tiles, one letter each.
///
/// Used for a game's hero art and for the word on the completion screen. The
/// tiles land one after another; under reduce motion they are simply there.
/// A word too long for its space shrinks to fit rather than overflowing.
class GameLetterTiles extends StatefulWidget {
  const GameLetterTiles({
    super.key,
    required this.word,
    this.tileSize = 40,
    this.animate = true,
  });

  final String word;
  final double tileSize;

  /// False draws the word at rest, for art that should not move.
  final bool animate;

  @override
  State<GameLetterTiles> createState() => _GameLetterTilesState();
}

class _GameLetterTilesState extends State<GameLetterTiles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration(widget.word.length),
  );
  bool _started = false;

  static Duration _duration(int letters) =>
      GameMotion.enter + GameMotion.stagger * (letters > 1 ? letters - 1 : 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate || reduceMotionOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letters = widget.word.characters.toList();
    final total = _controller.duration!.inMicroseconds;

    return Semantics(
      label: widget.word,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < letters.length; i++)
                  if (letters[i].trim().isEmpty)
                    SizedBox(width: widget.tileSize * 0.5)
                  else
                    _letter(letters[i], i, total),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _letter(String letter, int index, int total) {
    final start = (GameMotion.stagger.inMicroseconds * index) / total;
    final end = (start + GameMotion.enter.inMicroseconds / total).clamp(
      0.0,
      1.0,
    );
    final t = Interval(
      start.clamp(0.0, 1.0),
      end,
      curve: GameMotion.settleCurve,
    ).transform(_controller.value);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.tileSize * 0.04),
      // A tile pops in from nothing: scale only, no fade. Fading a tile
      // and its shadow together means compositing them off-screen first,
      // and the overshoot in the curve gives the landing its life anyway.
      child: Transform.scale(
        key: ValueKey('game-letter-tile-$index'),
        scale: t < 0 ? 0 : t,
        child: GameTile(
          radius: widget.tileSize * 0.22,
          depth: widget.tileSize * 0.1,
          child: SizedBox.square(
            dimension: widget.tileSize,
            child: Center(
              child: Text(
                letter.toUpperCase(),
                // The letter is sized to its tile, which does not grow
                // with the reader's text size. Scaling one and not the
                // other pushes the glyph out of the tile. The word is
                // still read out in full, by the label above.
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: widget.tileSize * 0.56,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
