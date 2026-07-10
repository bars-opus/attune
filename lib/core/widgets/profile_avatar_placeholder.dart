import 'package:flutter/material.dart';

class ProfileAvatarPlaceholder extends StatelessWidget {
  final double size;
  final bool isEdtting;

  const ProfileAvatarPlaceholder({
    super.key,
    required this.size,
    this.isEdtting = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primary,
        border: Border.all(color: colorScheme.primary, width: 2),
      ),
      child: Center(
        child: Icon(
          isEdtting ? Icons.camera_alt : Icons.person,
          size: size * 0.5,
          color: colorScheme.background,
        ),
      ),
    );
  }
}
