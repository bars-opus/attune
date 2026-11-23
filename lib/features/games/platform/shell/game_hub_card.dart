import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';

/// The ink for words written on a block of [block]: white where white reads
/// at 4.5:1 or better, else [GameTheme.tileInk].
///
/// The card titles are not large enough to count as large text, so they
/// need 4.5:1. White on every launch colour is between 3.2 and 3.9; the
/// tile ink on each is 4.8 or more. Decided from the colour rather than
/// listed per game, so a game added later gets readable words too.
Color hubCardInk(Color block) {
  return _contrast(GameTheme.onGround, block) >= 4.5
      ? GameTheme.onGround
      : GameTheme.tileInk;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// A game in the hub: a block of its colour, a white tile with its icon,
/// its name. [onTap] null draws it dimmed and takes no touches.
class GameHubCard extends StatelessWidget {
  const GameHubCard({
    super.key,
    required this.definition,
    this.onTap,
    this.featured = false,
  });

  final GameDefinition definition;
  final VoidCallback? onTap;

  /// The one big card at the top of the launch games: taller, a larger
  /// title, and its tagline.
  final bool featured;

  /// The least a card is tall. Larger text makes it taller, never clipped.
  static const double featuredHeight = 150;
  static const double height = 120;

  /// The space between a card's edge and what is on it.
  static const double padding = 14;

  /// A card's name, less its colour.
  static const TextStyle titleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    height: 1.15,
  );

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final primary = definition.theme.primary;
    // Dimmed through the colours, not an Opacity widget: the block sinks
    // toward the ground, the tile lies flat, the words go quiet.
    final block =
        enabled ? primary : Color.lerp(primary, GameTheme.ground, 0.5)!;
    final ink = enabled ? hubCardInk(block) : GameTheme.mutedOnGround;

    final card = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: featured ? featuredHeight : height,
      ),
      child: DecoratedBox(
        key: const ValueKey('game-hub-card-block'),
        decoration: BoxDecoration(
          color: block,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: EdgeInsets.all(featured ? 18 : padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GameTile(
                // A still piece: the card is what is pressed.
                color: enabled ? GameTheme.tile : primary,
                depth: enabled ? 4 : 0,
                radius: 12,
                padding: EdgeInsets.all(featured ? 10 : 8),
                child: Icon(
                  definition.icon,
                  size: featured ? 30 : 24,
                  color: enabled ? GameTheme.tileInk : GameTheme.mutedOnGround,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      definition.title,
                      style: titleStyle.copyWith(
                        color: ink,
                        fontSize: featured ? 26 : null,
                      ),
                    ),
                    if (featured) ...[
                      const SizedBox(height: 4),
                      Text(
                        definition.tagline,
                        style: TextStyle(
                          color: ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: enabled,
      label:
          enabled
              ? definition.title
              : GameStrings.comingSoonNamed(definition.title),
      onTap: onTap,
      child: enabled ? _PressDown(onTap: onTap!, child: card) : card,
    );
  }
}

/// Sinks a little under a finger, so the card answers the touch.
class _PressDown extends StatefulWidget {
  const _PressDown({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressDown> createState() => _PressDownState();
}

class _PressDownState extends State<_PressDown> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: GameMotion.of(context, GameMotion.press),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
