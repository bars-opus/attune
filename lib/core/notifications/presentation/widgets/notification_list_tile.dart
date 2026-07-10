// lib/features/notifications/presentation/widgets/notification_list_tile.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/core/notifications/utils/notification_date_time_utils.dart';

/// Reusable notification list tile with read/unread state
class NotificationListTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismissed;

  const NotificationListTile({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed?.call(),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: Spacing.lg.w),
        child: Icon(Icons.delete_outline, color: Colors.white, size: 24.w),
      ),
      child: Material(
        color:
            notification.isRead
                ? Colors.transparent
                : colorScheme.primaryContainer.withValues(alpha:0.3),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: Spacing.md.w,
              vertical: Spacing.md.h,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outline.withValues(alpha:0.1),
                  width: BorderWidthTokens.hairline,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha:0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIconForType(notification.data?['type'] as String?),
                    color: colorScheme.primary,
                    size: 20.w,
                  ),
                ),
                Gap(Spacing.md.w),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight:
                              notification.isRead
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                          color:
                              notification.isRead
                                  ? colorScheme.onSurface.withValues(alpha:0.7)
                                  : colorScheme.onSurface,
                        ),
                      ),
                      Gap(Spacing.xs.h),
                      Text(
                        notification.body,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha:0.6),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Gap(Spacing.xs.h),
                      Text(
                        NotificationDateTimeUtils.timeAgo(
                          notification.createdAt,
                        ),
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha:0.4),
                          fontSize: 10.sp,
                        ),
                      ),
                    ],
                  ),
                ),

                // Unread indicator
                if (!notification.isRead)
                  Container(
                    width: 8.w,
                    height: 8.w,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'booking_reminder_24h':
      case 'booking_reminder_1h':
      case 'booking_reminder_5min':
        return Icons.event_available;
      case 'shop_reminder_15min':
        return Icons.storefront;
      case 'review_request':
        return Icons.rate_review;
      case 'new_booking':
        return Icons.book_online;
      case 'new_shop_nearby':
        return Icons.store;
      case 'new_review_shop':
        return Icons.star;
      default:
        return Icons.notifications;
    }
  }
}
