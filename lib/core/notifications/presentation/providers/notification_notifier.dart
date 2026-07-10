import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/notifications/domain/usecases/delete_notification.dart';
import 'package:attune/core/notifications/domain/usecases/get_unread_count.dart';
import 'package:attune/core/notifications/domain/usecases/get_user_notifications.dart';
import 'package:attune/core/notifications/domain/usecases/mark_all_notifications_as_read.dart';
import 'package:attune/core/notifications/domain/usecases/mark_notification_as_read.dart';
import 'package:attune/core/notifications/presentation/providers/notification_state.dart';

class NotificationNotifier extends StateNotifier<NotificationListState> {
  final GetUserNotificationsUseCase _getUserNotificationsUseCase;
  final MarkNotificationAsReadUseCase _markAsReadUseCase;
  final MarkAllNotificationsAsReadUseCase _markAllAsReadUseCase;
  final DeleteNotificationUseCase _deleteNotificationUseCase;
  final GetUnreadCountUseCase _getUnreadCountUseCase;
  final String _userId;

  NotificationNotifier({
    required GetUserNotificationsUseCase getUserNotificationsUseCase,
    required MarkNotificationAsReadUseCase markAsReadUseCase,
    required MarkAllNotificationsAsReadUseCase markAllAsReadUseCase,
    required DeleteNotificationUseCase deleteNotificationUseCase,
    required GetUnreadCountUseCase getUnreadCountUseCase,
    required String userId,
  }) : _getUserNotificationsUseCase = getUserNotificationsUseCase,
       _markAsReadUseCase = markAsReadUseCase,
       _markAllAsReadUseCase = markAllAsReadUseCase,
       _deleteNotificationUseCase = deleteNotificationUseCase,
       _getUnreadCountUseCase = getUnreadCountUseCase,
       _userId = userId,
       super(NotificationListState.initial());

  Future<void> loadNotifications() async {
    if (_userId.isEmpty) {
      state = state.copyWith(notifications: [], isLoading: false);
      return;
    }

    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final notifications = await _getUserNotificationsUseCase(_userId);
      state = state.copyWith(
        notifications: notifications,
        isLoading: false,
        hasMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load notifications: $e',
      );
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _markAsReadUseCase(notificationId);

      final updated = state.notifications.map((n) {
        if (n.id == notificationId) {
          return n.copyWith(isRead: true, readAt: DateTime.now());
        }
        return n;
      }).toList();

      state = state.copyWith(notifications: updated);
    } catch (e) {
      // Silently ignore — the optimistic update already happened for single-read,
      // which is fine; the user can retry on next load.
    }
  }

  /// Marks all unread notifications as read in a single batch query.
  Future<void> markAllAsRead() async {
    if (_userId.isEmpty) return;
    try {
      await _markAllAsReadUseCase(_userId);

      final now = DateTime.now();
      final updated = state.notifications.map((n) {
        return n.copyWith(isRead: true, readAt: now);
      }).toList();

      state = state.copyWith(notifications: updated);
    } catch (e) {
      // Non-fatal — list will be consistent on next refresh.
    }
  }

  Future<void> refresh() async {
    await loadNotifications();
  }

  /// Deletes a notification both from the DB and from local state.
  Future<void> deleteNotification(String notificationId) async {
    // Optimistic removal for instant UI response.
    final updated = state.notifications
        .where((n) => n.id != notificationId)
        .toList();
    state = state.copyWith(notifications: updated);

    try {
      await _deleteNotificationUseCase(notificationId);
    } catch (e) {
      // Reload to restore accurate state if the DB delete failed.
      await loadNotifications();
    }
  }

  Future<int> getUnreadCount() async {
    try {
      return await _getUnreadCountUseCase(_userId);
    } catch (e) {
      return 0;
    }
  }
}
