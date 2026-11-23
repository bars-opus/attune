import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';

/// The round translucent button in a game's header and action row.
///
/// 48 across, so it clears the minimum touch target on its own. With a
/// [caption] it becomes one of the labelled actions under a board.
class GameRoundButton extends StatelessWidget {
  const GameRoundButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.caption,
    this.size = 48,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final String? caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      type: MaterialType.circle,
      color: GameTheme.onGround.withValues(alpha: 0.16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, color: GameTheme.onGround, size: size * 0.5),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      container: true,
      excludeSemantics: true,
      onTap: onTap,
      child:
          caption == null
              ? button
              : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button,
                  const SizedBox(height: 6),
                  Text(
                    caption!,
                    style: const TextStyle(
                      color: GameTheme.mutedOnGround,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
    );
  }
}

/// The big white pill: Play, Continue, Play again.
///
/// Disabled, it dims and stops answering, and says so to a screen reader --
/// "Waiting for Ama" is information, not an action.
///
/// [busy] is for the wait after a tap, while the thing it asked for is
/// being made: a progress ring takes the icon's place and the button is
/// disabled until it clears, so a second tap cannot ask twice.
class GamePrimaryButton extends StatefulWidget {
  const GamePrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  State<GamePrimaryButton> createState() => _GamePrimaryButtonState();
}

class _GamePrimaryButtonState extends State<GamePrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    // Letting go always counts, so a button that went busy under a finger
    // is not left pressed in.
    if (value && (widget.onTap == null || widget.busy)) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.busy ? null : widget.onTap;
    final enabled = onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      container: true,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: onTap,
        child: AnimatedScale(
          scale: _pressed && enabled ? 0.97 : 1,
          duration: GameMotion.of(context, GameMotion.press),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              // Dimmed through the colour, not an Opacity widget, which
              // would composite the whole pill off-screen to fade it.
              color:
                  enabled
                      ? GameTheme.tile
                      : GameTheme.tile.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.busy) ...[
                  SizedBox.square(
                    dimension: 20,
                    // Under reduced motion it holds still, as a ring with a
                    // gap: every other moving thing in the games stops there
                    // too, and the dimmed pill already says "wait".
                    child: CircularProgressIndicator(
                      value: reduceMotionOf(context) ? 0.75 : null,
                      strokeWidth: 2.5,
                      color: GameTheme.tileInk,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (widget.icon != null) ...[
                  Icon(widget.icon, color: GameTheme.tileInk, size: 26),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: GameTheme.tileInk,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The quieter outlined pill beside or under a primary button.
class GameSecondaryButton extends StatelessWidget {
  const GameSecondaryButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      container: true,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: GameTheme.onGround.withValues(alpha: 0.5),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameTheme.onGround,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
