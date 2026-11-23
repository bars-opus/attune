import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';

/// The white tile every game is built from.
///
/// A flat face over a hard offset shadow. Pressed, the face moves down onto
/// its shadow, so a tap reads as pushing a real key. Letters, options, board
/// cells and hero art are all this one widget.
///
/// There is no blur anywhere in it: two flat rounded rectangles are about the
/// cheapest thing a phone can draw, which matters on low-end hardware.
class GameTile extends StatefulWidget {
  const GameTile({
    super.key,
    required this.child,
    this.onTap,
    this.color = GameTheme.tile,
    this.shadowColor = GameTheme.tileShadow,
    this.radius = 12,
    this.depth = 5,
    this.padding = EdgeInsets.zero,
    this.semanticLabel,
    this.selected,
  });

  final Widget child;

  /// Null makes the tile a still piece: it does not press and is not
  /// announced as a button.
  final VoidCallback? onTap;

  final Color color;
  final Color shadowColor;
  final double radius;

  /// How far the shadow sits below the face, and how far a press travels.
  final double depth;

  final EdgeInsetsGeometry padding;

  /// Replaces the child's own text for a screen reader when set.
  final String? semanticLabel;

  /// Announced to a screen reader when this tile is a choice.
  final bool? selected;

  /// The shadow sits this share of [depth] to the right of the face.
  static const double lean = 0.6;

  @override
  State<GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<GameTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final dx = widget.depth * GameTile.lean;
    final dy = widget.depth;
    final radius = BorderRadius.circular(widget.radius);

    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      selected: widget.selected,
      container: true,
      excludeSemantics: widget.semanticLabel != null,
      // The tap is announced here, not by the detector below, so a tile
      // is one thing to a screen reader whether or not it has a label.
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        // The padding reserves the room the shadow needs, so a tile's
        // layout size never changes when it is pressed.
        child: Padding(
          padding: EdgeInsets.only(right: dx, bottom: dy),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(dx, dy),
                  child: DecoratedBox(
                    key: const ValueKey('game-tile-shadow'),
                    decoration: BoxDecoration(
                      color: widget.shadowColor,
                      borderRadius: radius,
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                key: const ValueKey('game-tile-face'),
                duration: GameMotion.of(context, GameMotion.press),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(
                  _pressed ? dx : 0,
                  _pressed ? dy : 0,
                  0,
                ),
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: radius,
                ),
                child: IconTheme.merge(
                  data: const IconThemeData(color: GameTheme.tileInk),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      color: GameTheme.tileInk,
                      fontWeight: FontWeight.w800,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
