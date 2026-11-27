// Glass buttons: a round icon button, a capsule (icon and or label) and the
// one solid "primary" circle the glass ones sit beside (Journal's ›).
import 'package:attune/core/ui/glass/glass_pressable.dart';
import 'package:attune/core/ui/glass/liquid_glass.dart';
import 'package:flutter/material.dart';

/// A round glass button holding one icon (at least 44 x 44 to tap).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 44,
    this.iconSize = 20,
    this.variant = GlassVariant.regular,
    this.color,
    this.refract = true,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Read by screen readers and shown on long press.
  final String tooltip;
  final double size;
  final double iconSize;
  final GlassVariant variant;
  final Color? color;
  final bool refract;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurface;
    // One label, one tap action for screen readers (final review I3).
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        onTap: onPressed,
        excludeSemantics: true,
        child: GlassPressable(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: LiquidGlass(
              variant: variant,
              refract: refract,
              refraction: size * 0.22,
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: onPressed == null ? fg.withValues(alpha: 0.38) : fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A glass capsule: an icon, a label, or both ("Go deeper", "+ Seneca").
class GlassCapsuleButton extends StatelessWidget {
  const GlassCapsuleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = GlassVariant.regular,
    this.height = 44,
    this.refract = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final GlassVariant variant;
  final double height;
  final bool refract;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface.withValues(alpha: onPressed == null ? 0.38 : 1);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: GlassPressable(
        onTap: onPressed,
        pressedScale: 0.95,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height, minWidth: height),
          child: LiquidGlass(
            variant: variant,
            refract: refract,
            refraction: height * 0.22,
            padding: EdgeInsets.symmetric(horizontal: height * 0.42),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
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

/// The solid circle for the one main action among glass buttons.
class GlassPrimaryCircle extends StatelessWidget {
  const GlassPrimaryCircle({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 48,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? Colors.white : scheme.primary;
    final fg = dark ? Colors.black : scheme.onPrimary;
    // One label, one tap action for screen readers (final review I3).
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        onTap: onPressed,
        excludeSemantics: true,
        child: GlassPressable(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: onPressed == null ? bg.withValues(alpha: 0.38) : bg,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
              ],
            ),
            child: Icon(icon, color: fg, size: size * 0.45),
          ),
        ),
      ),
    );
  }
}
