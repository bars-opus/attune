// lib/core/widgets/icon_avatar.dart
import 'package:attune/core/utils/exports/export_screens.dart';

class IconAvatar extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final Color? backgroundColor;
  final double? size;
  final bool showAvatar;
  final double circularRadius;
  // Controls the icon size in avatar mode via radius * 0.8.
  // Prefer passing [size] directly; this param exists for callsite compatibility.
  final double? avatarRadiusSize;

  const IconAvatar({
    super.key,
    required this.icon,
    this.iconColor,
    this.backgroundColor,
    this.size,
    this.showAvatar = false,
    this.circularRadius = BorderRadiusTokens.full,
    this.avatarRadiusSize,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final icoColor = iconColor ?? colorScheme.primary;
    final bgColor =
        backgroundColor ?? colorScheme.primary.withValues(alpha: 0.1);

    if (showAvatar) {
      final radius = avatarRadiusSize ?? 40.r;
      final iconSize = size ?? radius * 0.8;

      return Container(
        padding: const EdgeInsets.all(Spacing.sm),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(circularRadius),
        ),
        child: Icon(icon, size: iconSize, color: icoColor),
      );
    }

    return Icon(icon, size: size ?? 24.r, color: icoColor);
  }
}
