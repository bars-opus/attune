import 'package:flutter/foundation.dart';

/// Lightweight client-side notification adapter.
///
/// Attune's production push delivery should flow through the notification
/// engine/server-side pipeline, not direct device-originated push sends.
/// For the current runtime cleanup pass we keep these calls non-breaking so
/// relationship features compile and manual testing can proceed.
class AttuneNotificationService {
  Future<void> sendPulseUpdated({
    required String userId,
    required int newScore,
    int? delta,
  }) async {
    debugPrint(
      '[notifications] pulse_updated user=$userId score=$newScore delta=$delta',
    );
  }

  Future<void> notifyPartnerMomentLogged({
    required String partnerId,
    required String partnerName,
    required String eventType,
    required String title,
  }) async {
    debugPrint(
      '[notifications] partner_moment_logged partner=$partnerId '
      'name=$partnerName type=$eventType title=$title',
    );
  }
}
