import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:flutter/material.dart';

/// The map's floating surface: translucent, not blurred. A BackdropFilter
/// over the Mapbox platform view is unreliable on Android hybrid
/// composition and costly (spec §7 risk); a 90 % surface with a hairline
/// border reads the same and follows the theme.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = BorderRadiusTokens.lgAll,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.9),
        borderRadius: borderRadius,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.6),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A 44 dp round glass button with a tooltip and a matching label.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const size = CoupleMapConfig.glassButtonSize;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        // excludeSemantics drops the InkWell's action: give it back.
        onTap: onPressed,
        excludeSemantics: true,
        // A 48 dp hit area (Android guideline) around the 44 dp circle. The
        // ripple stays inside the circle: the InkWell is in the panel, and
        // the extra ring is a translucent detector the inner one beats.
        child: SizedBox.square(
          dimension: CoupleMapConfig.glassTarget,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onPressed,
            child: Center(
              child: SizedBox.square(
                dimension: size,
                child: GlassPanel(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(size / 2),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onPressed,
                      child: Icon(icon, size: 22, color: cs.onSurface),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
