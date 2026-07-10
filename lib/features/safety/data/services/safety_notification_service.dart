// lib/features/safety/data/services/safety_notification_service.dart

import 'package:flutter/foundation.dart';

class SafetyNotificationService {
  static Future<void> sendSafetyNotification({
    required String playerId,
    required String eventToken,
  }) async {
    debugPrint(
      '[safety-notification] suppressed client-side push send '
      'player=$playerId event=$eventToken',
    );
  }
}
