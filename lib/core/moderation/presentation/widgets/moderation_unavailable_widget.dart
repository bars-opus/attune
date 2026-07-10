// lib/features/moderation/presentation/widgets/moderation_unavailable_widget.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';


class ModerationUnavailableWidget extends StatelessWidget {
  final String type; // 'profile', 'content', 'chat'
  final VoidCallback? onGoBack;

  const ModerationUnavailableWidget({
    super.key,
    required this.type,
    this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    String title;
    String message;
    IconData icon;

    switch (type) {
      case 'profile':
        title = 'Profile unavailable';
        message = 'This user has blocked you or been blocked.';
        icon = Icons.block_outlined;
        break;
      case 'content':
        title = 'Content unavailable';
        message = 'This content is no longer available.';
        icon = Icons.visibility_off_outlined;
        break;
      case 'chat':
        title = 'Chat unavailable';
        message = 'You can\'t chat with this user at this time.';
        icon = Icons.chat_bubble_outline;
        break;
      default:
        title = 'Unavailable';
        message = 'This content is not available.';
        icon = Icons.error_outline;
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: colorScheme.onSurface.withOpacity(0.5)),
            Gap(Spacing.lg.h),
            Text(
              title,
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.md.h),
            Text(
              message,
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onGoBack != null) ...[
              Gap(Spacing.xl.h),
              AppButton(
                label: 'Go back',
                onPressed: onGoBack,
                // size: ButtonSize.medium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
