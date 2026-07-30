// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:io';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/profile_avatar_placeholder.dart';




class ProfileAvatar extends StatelessWidget {
  String avatarUrl;
  String currentUserId;
  final bool enableHero;

  final double size;

  /// Renders a status glyph instead of the generic person placeholder when
  /// [avatarUrl] is empty — e.g. relationship-status icons, the same pattern
  /// OpinionCard uses via IconAvatar/InfoRowWidget. Ignored once [avatarUrl]
  /// is non-empty; a real photo always takes precedence over a status icon.
  final IconData? icon;

  /// Color of [icon]. Defaults to [colorScheme.background] (white in light
  /// mode, black in dark mode) so it reads against a colored [backgroundColor]
  /// the same way the status icon does on OpinionCard.
  final Color? iconColor;

  /// Fill color behind [icon]. Defaults to [colorScheme.primary]. Pass a
  /// status color (e.g. from the same status→color mapping OpinionCard uses)
  /// to make the avatar adapt to relationship status.
  final Color? backgroundColor;

  ProfileAvatar({
    Key? key,
    required this.avatarUrl,
    required this.currentUserId,
    required this.size,
    this.enableHero = true,
    this.icon,
    this.iconColor,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    _header() {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.surface, width: 3.w),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8.r,
              offset: Offset(0, 2.h),
            ),
          ],
        ),
        child: ClipOval(
          child:
              avatarUrl.isNotEmpty
                  ? (avatarUrl.startsWith('http')
                      ? CachedNetworkImage(
                        imageUrl: avatarUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _buildPlaceholder(colorScheme),
                        errorWidget:
                            (_, __, ___) => _buildPlaceholder(colorScheme),
                      )
                      : Image.file(
                        File(avatarUrl),
                        fit: BoxFit.cover,
                        errorBuilder:
                            (context, error, stackTrace) =>
                                _buildPlaceholder(colorScheme),
                      ))
                  : _buildPlaceholder(colorScheme),
        ),
      );
    }

    return enableHero ? Hero(tag: currentUserId, child: _header()) : _header();
  }

  // Icon size is always relative to the avatar's own container (size * 0.5),
  // matching ProfileAvatarPlaceholder's ratio — so a status icon scales with
  // wherever this avatar is placed instead of needing its own size param.
  Widget _buildPlaceholder(ColorScheme colorScheme) {
    if (icon == null) return ProfileAvatarPlaceholder(size: size);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? colorScheme.primary,
      ),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.5,
          color: iconColor ?? colorScheme.background,
        ),
      ),
    );
  }
}
