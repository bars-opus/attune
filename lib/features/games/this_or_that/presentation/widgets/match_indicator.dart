import 'dart:math' as math;

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

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 16,
  );
  static const double _icon = 24;
  static const double _iconGap = 10;

  /// The border, one pixel on each side.
  static const double _border = 1;

  static String _title(bool isMatch) =>
      isMatch ? 'Same wavelength' : 'A new thing to know';

  static String _line(bool isMatch) =>
      isMatch
          ? 'You both reached for the same side.'
          : 'Different picks make the best conversations.';

  static TextStyle? _titleStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
        color: ThisOrThatPalette.of(context).ink,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      );

  static TextStyle? _lineStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
        color: ThisOrThatPalette.of(context).mutedInk,
        letterSpacing: 0,
      );

  /// How tall the verdict is drawn [width] wide, in [context]'s theme and
  /// text size: a screen that must keep it in view measures it rather than
  /// guessing, since the app's text theme sets taller lines than a plain one.
  static double heightFor(
    BuildContext context, {
    required bool isMatch,
    required double width,
  }) {
    final textWidth =
        width - _padding.horizontal - _border * 2 - _icon - _iconGap;
    double measure(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: math.max(0, textWidth));
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final words =
        measure(_title(isMatch), _titleStyle(context)) +
        measure(_line(isMatch), _lineStyle(context));
    return _padding.vertical + _border * 2 + math.max(_icon, words);
  }

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
          padding: _padding,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: _border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isMatch ? Icons.favorite_rounded : Icons.explore_outlined,
                color: accent,
                size: _icon,
              ),
              const SizedBox(width: _iconGap),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title(isMatch), style: _titleStyle(context)),
                    Text(_line(isMatch), style: _lineStyle(context)),
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
