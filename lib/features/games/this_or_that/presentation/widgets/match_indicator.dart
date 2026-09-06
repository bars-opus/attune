import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';

class MatchIndicator extends StatelessWidget {
  const MatchIndicator({
    super.key,
    required this.isMatch,
    required this.animation,
  });

  final bool isMatch;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final accent = isMatch ? palette.thisColor : palette.thatColor;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: 0.92 + (value * 0.08), child: child),
        );
      },
      child: Semantics(
        liveRegion: true,
        label:
            isMatch
                ? 'You matched. You both chose the same answer.'
                : 'Different picks. You chose different answers.',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isMatch ? Icons.favorite_rounded : Icons.explore_outlined,
                color: accent,
                size: 24,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMatch ? 'Same wavelength' : 'A new thing to know',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    Text(
                      isMatch
                          ? 'You both reached for the same side.'
                          : 'Different picks make the best conversations.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.mutedInk,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
