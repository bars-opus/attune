// lib/features/notifications/presentation/providers/notification_provider.dart
import 'package:attune/core/notifications/services/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/core/notifications/data/repositories/notification_repository_impl.dart';
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/core/notifications/domain/usecases/cancel_booking_notifications.dart';
import 'package:attune/core/notifications/domain/usecases/delete_notification.dart';
import 'package:attune/core/notifications/domain/usecases/get_unread_count.dart';
import 'package:attune/core/notifications/domain/usecases/get_user_notifications.dart';
import 'package:attune/core/notifications/domain/usecases/mark_all_notifications_as_read.dart';
import 'package:attune/core/notifications/domain/usecases/mark_notification_as_read.dart';
import 'package:attune/core/notifications/domain/usecases/notify_new_shop_nearby.dart';
import 'package:attune/core/notifications/domain/usecases/register_push_token.dart';
import 'package:attune/core/notifications/domain/usecases/schedule_booking_reminders.dart';
import 'package:attune/core/notifications/domain/usecases/send_immediate_notification.dart';
import 'package:attune/core/notifications/presentation/providers/notification_notifier.dart';
import 'package:attune/core/notifications/presentation/providers/notification_settings_notifier.dart';
import 'notification_state.dart';

// ===========================================
// Repository Provider
// ============================================

final notificationRepositoryProvider =
    Provider<NotificationRepositoryInterface>((ref) {
      final supabase = ref.read(supabaseClientProvider);
      return NotificationRepositoryImpl(supabase);
    });

// ============================================
// Use Case Providers
// ============================================

final scheduleBookingRemindersUseCaseProvider = Provider((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return ScheduleBookingRemindersUseCase(repository);
});

final sendImmediateNotificationUseCaseProvider = Provider((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return SendImmediateNotificationUseCase(repository);
});

final cancelBookingNotificationsUseCaseProvider = Provider((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return CancelBookingNotificationsUseCase(repository);
});

final registerPushTokenUseCaseProvider = Provider((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return RegisterPushTokenUseCase(repository);
});

final notifyNewShopNearbyUseCaseProvider = Provider((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return NotifyNewShopNearbyUseCase(repository);
});

final getUserNotificationsUseCaseProvider = Provider((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return GetUserNotificationsUseCase(repository);
});

final markNotificationAsReadUseCaseProvider = Provider((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return MarkNotificationAsReadUseCase(repository);
});

final getUnreadCountUseCaseProvider = Provider((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return GetUnreadCountUseCase(repository);
});

final markAllNotificationsAsReadUseCaseProvider = Provider((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return MarkAllNotificationsAsReadUseCase(repository);
});

final deleteNotificationUseCaseProvider = Provider((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return DeleteNotificationUseCase(repository);
});

// ============================================
// Service Provider
// ============================================

// final notificationServiceProvider = Provider<NotificationService>((ref) {
//   return NotificationService(
//     scheduleRemindersUseCase: ref.read(scheduleBookingRemindersUseCaseProvider),
//     sendImmediateUseCase: ref.read(sendImmediateNotificationUseCaseProvider),
//     cancelBookingUseCase: ref.read(cancelBookingNotificationsUseCaseProvider),
//     registerPushTokenUseCase: ref.read(registerPushTokenUseCaseProvider),
//     notifyNewShopNearbyUseCase: ref.read(notifyNewShopNearbyUseCaseProvider),
//     getUserNotificationsUseCase: ref.read(getUserNotificationsUseCaseProvider),
//     markAsReadUseCase: ref.read(markNotificationAsReadUseCaseProvider),
//     getUnreadCountUseCase: ref.read(getUnreadCountUseCaseProvider),
//   );
// });

// ============================================
// Notifier Providers (Stateful)
// ============================================

final notificationListProvider =
    StateNotifierProvider<NotificationNotifier, NotificationListState>((ref) {
      final user = ref.watch(currentUserProvider);
      final userId = user?.id;

      if (userId == null) {
        return NotificationNotifier(
          getUserNotificationsUseCase: ref.read(getUserNotificationsUseCaseProvider),
          markAsReadUseCase: ref.read(markNotificationAsReadUseCaseProvider),
          markAllAsReadUseCase: ref.read(markAllNotificationsAsReadUseCaseProvider),
          deleteNotificationUseCase: ref.read(deleteNotificationUseCaseProvider),
          getUnreadCountUseCase: ref.read(getUnreadCountUseCaseProvider),
          userId: '',
        );
      }

      return NotificationNotifier(
        getUserNotificationsUseCase: ref.read(getUserNotificationsUseCaseProvider),
        markAsReadUseCase: ref.read(markNotificationAsReadUseCaseProvider),
        markAllAsReadUseCase: ref.read(markAllNotificationsAsReadUseCaseProvider),
        deleteNotificationUseCase: ref.read(deleteNotificationUseCaseProvider),
        getUnreadCountUseCase: ref.read(getUnreadCountUseCaseProvider),
        userId: userId,
      );
    });

final notificationSettingsProvider = StateNotifierProvider<
  NotificationSettingsNotifier,
  NotificationSettingsState
>((ref) {
  final user = ref.watch(currentUserProvider);
  final userId = user?.id;

  if (userId == null) {
    return NotificationSettingsNotifier(
      repository: ref.read(notificationRepositoryProvider),
      userId: '',
    );
  }

  return NotificationSettingsNotifier(
    repository: ref.read(notificationRepositoryProvider),
    userId: userId,
  );
});

// ============================================
// Reactive Unread Count
// ============================================

// Derived from the real-time stream so the badge updates instantly when new
// notifications arrive — no polling, no manual refresh needed.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final notificationsAsync = ref.watch(realTimeNotificationsProvider);
  return notificationsAsync.valueOrNull?.where((n) => !n.isRead).length ?? 0;
});

// ============================================
// Real-time Notification Subscription
// ============================================

final realTimeNotificationsProvider = StreamProvider<List<AppNotification>>((
  ref,
) async* {
  final user = ref.watch(currentUserProvider);
  final userId = user?.id;

  if (userId == null) {
    yield [];
    return;
  }

  final supabase = ref.read(supabaseClientProvider);

  final useCase = ref.read(getUserNotificationsUseCaseProvider);
  final initialNotifications = await useCase(userId);
  yield initialNotifications;

  final stream = supabase
      .from('in_app_notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('created_at', ascending: false);

  await for (final _ in stream) {
    final updatedNotifications = await useCase(userId);
    yield updatedNotifications;
  }
});

// ============================================
// Combined Provider for Notification UI
// ============================================

final authenticatedNotificationsProvider = Provider((ref) {
  final authState = ref.watch(authStateProvider);
  final isAuthenticated = authState.valueOrNull != null;

  return AuthenticatedNotifications(
    isAuthenticated: isAuthenticated,
    notificationList: ref.watch(notificationListProvider),
    unreadCount: ref.watch(unreadNotificationCountProvider),
    settings: ref.watch(notificationSettingsProvider),
  );
});

class AuthenticatedNotifications {
  final bool isAuthenticated;
  final NotificationListState notificationList;
  final int unreadCount;
  final NotificationSettingsState settings;

  const AuthenticatedNotifications({
    required this.isAuthenticated,
    required this.notificationList,
    required this.unreadCount,
    required this.settings,
  });

  bool get shouldShowNotifications => isAuthenticated;
}
