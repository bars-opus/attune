import 'package:flutter/foundation.dart';

/// Temporary non-breaking adapter for Pulse notification intents.
///
/// Direct client-originated push creation is intentionally disabled in this
/// runtime cleanup pass because the current OneSignal SDK surface no longer
/// supports the legacy calls that were cloned from the old app.
/// Production delivery should move through the shared notification engine.
class PulseNotificationService {
  static Future<void> sendCheckinReminder(
    String userId,
    String partnerName,
  ) async {
    debugPrint('[pulse] checkin_reminder user=$userId partner=$partnerName');
  }

  static Future<void> sendPulseUpdated(
    String userId,
    int newScore,
    int? delta,
  ) async {
    debugPrint(
      '[pulse] pulse_updated user=$userId score=$newScore delta=$delta',
    );
  }

  static Future<void> sendPartnerMomentLogged(
    String userId,
    String partnerName,
    String eventType,
    String title,
  ) async {
    debugPrint(
      '[pulse] moment_logged user=$userId partner=$partnerName '
      'type=$eventType title=$title',
    );
  }
}
