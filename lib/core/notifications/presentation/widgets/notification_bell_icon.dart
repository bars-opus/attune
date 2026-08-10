// lib/features/notifications/presentation/widgets/notification_bell_icon.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/core/notifications/presentation/providers/notification_provider.dart';

/// Notification bell icon with unread count badge
/// Automatically shows/hides based on auth state
class NotificationBellIcon extends ConsumerWidget {
  final VoidCallback? onPressed;
  final double iconSize;
  final Color? iconColor;

  const NotificationBellIcon({
    super.key,
    this.onPressed,
    this.iconSize = 24,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final isLoggedIn = authState.valueOrNull != null;

    // Don't show notification bell if not logged in
    if (!isLoggedIn) {
      return const SizedBox.shrink();
    }

    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            Icons.notifications_outlined,
            size: iconSize.w,
            color: iconColor,
          ),
          onPressed:
              onPressed ??
              () {
                context.pushNamed('notificationInbox');
              },
        ),
        if (unreadCount > 0)
          Positioned(
            right: 8.w,
            top: 8.h,
            child: Container(
              padding: EdgeInsets.all(Spacing.xs.w),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: BorderWidthTokens.hairline,
                ),
              ),
              constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.h),
              // Above the cap is a fixed "99+" display, not a real count to
              // roll toward — AnimatedRollingCounter only takes over for the
              // actual animated range (0-99); the badge falls back to plain
              // Text once it's capped, same as the old _formatCount did.
              child:
                  unreadCount > 99
                      ? Text(
                        '99+',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      )
                      : AnimatedRollingCounter(
                        count: unreadCount,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
            ),
          ),
      ],
    );
  }
}
