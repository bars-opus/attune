import 'package:flutter/material.dart';

import 'neon_quality.dart';
import 'neon_tokens.dart';

/// The ground, and the barely-there glow that gives it a middle.
///
/// Spec §2.1 tier 1: the ground receives light and emits none. Without
/// the well a neon field is a flat void -- correct, and dead. With it
/// there is a centre for the composition to sit in, at an alpha low
/// enough that nobody would describe the screen as having a gradient.
///
/// Degrading drops the falloff but NEVER the ground: a transparent
/// ground would fall through to the app theme, which in light mode is
/// white, and every colour in this language was chosen against
/// near-black.
class LightWell extends StatelessWidget {
  const LightWell({super.key, this.tint, this.child});

  /// The hue of the well. Defaults to a neutral lift.
  final Color? tint;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final quality = neonQualityOf(context);
    final colour = tint ?? const Color(0xFFFFFFFF);

    return DecoratedBox(
      decoration: BoxDecoration(color: NeonTokens.groundColor),
      child:
          quality == NeonQuality.plain
              // Ground only. The gradient is the first thing to go.
              ? (child ?? const SizedBox.expand())
              : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: NeonTokens.lightWellRadiusRatio,
                    colors: [
                      colour.withValues(alpha: NeonTokens.lightWellAlpha),
                      colour.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: child ?? const SizedBox.expand(),
              ),
    );
  }
}
