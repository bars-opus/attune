// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:io';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/profile_avatar_placeholder.dart';




class ProfileAvatar extends StatelessWidget {
  String avatarUrl;
  String currentUserId;
  final bool enableHero;

  final double size;
  ProfileAvatar({
    Key? key,
    required this.avatarUrl,
    required this.currentUserId,
    required this.size,
    this.enableHero = true,
  }) : super(key: key);
  // Widget _buildAvatarPlaceholder(ColorScheme colorScheme, double size) {
  //   return
  // }

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
                        placeholder: (_, __) => ProfileAvatarPlaceholder(size: size),
                        errorWidget: (_, __, ___) => ProfileAvatarPlaceholder(size: size),
                      )
                      : Image.file(
                        File(avatarUrl),
                        fit: BoxFit.cover,
                        errorBuilder:
                            (context, error, stackTrace) =>
                                ProfileAvatarPlaceholder(size: size),
                      ))
                  : ProfileAvatarPlaceholder(size: size),
        ),
      );
    }

    return enableHero ? Hero(tag: currentUserId, child: _header()) : _header();
  }
}
