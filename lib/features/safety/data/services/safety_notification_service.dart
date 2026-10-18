// lib/features/safety/data/services/safety_notification_service.dart

class SafetyNotificationService {
  static Future<void> sendSafetyNotification({
    required String playerId,
    required String eventToken,
  }) async {
    // Client-side safety pushes are suppressed. Nothing is logged: a device
    // log must not hold a push id (Spec 2).
  }
}
