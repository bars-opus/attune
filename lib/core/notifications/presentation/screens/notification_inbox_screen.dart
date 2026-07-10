import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/core/notifications/presentation/providers/notification_notifier.dart';
import 'package:attune/core/notifications/presentation/providers/notification_provider.dart';
import 'package:attune/core/notifications/presentation/providers/notification_state.dart';
import 'package:attune/core/notifications/presentation/widgets/notification_list_tile.dart';
import 'package:attune/core/widgets/feedback/circular_loading_indicator.dart';

class NotificationInboxScreen extends ConsumerStatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  ConsumerState<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState
    extends ConsumerState<NotificationInboxScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(notificationListProvider.notifier).loadNotifications(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final notificationState = ref.watch(notificationListProvider);
    final notifier = ref.read(notificationListProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (notificationState.notifications.isNotEmpty)
            TextButton(
              onPressed: () => notifier.markAllAsRead(),
              child: Text(
                'Mark all as read',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(notificationState, notifier),
    );
  }

  Widget _buildBody(
    NotificationListState state,
    NotificationNotifier notifier,
  ) {
    if (state.isLoading && state.notifications.isEmpty) {
      return const Center(child: CircularLoadingIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48.w,
              color: Theme.of(context).colorScheme.error,
            ),
            Gap(Spacing.md.h),
            Text(
              state.error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.md.h),
            ElevatedButton(
              onPressed: () => notifier.loadNotifications(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 64.w,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha:0.3),
            ),
            Gap(Spacing.md.h),
            Text(
              'No notifications yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha:0.6),
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'We\'ll notify you when something arrives',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha:0.4),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => notifier.loadNotifications(),
      child: ListView.builder(
        itemCount: state.notifications.length,
        itemBuilder: (context, index) {
          final notification = state.notifications[index];
          return NotificationListTile(
            notification: notification,
            onTap: () => _handleTap(notification, notifier),
            onDismissed: () => notifier.deleteNotification(notification.id),
          );
        },
      ),
    );
  }

  Future<void> _handleTap(
    AppNotification notification,
    NotificationNotifier notifier,
  ) async {
    if (!notification.isRead) {
      await notifier.markAsRead(notification.id);
    }

    if (!mounted) return;

    // Delegate navigation to the app-specific config callback.
    // Apps configure this via notificationConfigProvider in ProviderScope.
    final config = ref.read(notificationConfigProvider);
    config.onNotificationTap?.call(notification, context);
  }
}
