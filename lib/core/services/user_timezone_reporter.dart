// lib/core/services/user_timezone_reporter.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tells the server which time zone this phone is in, so quiet hours
/// (22:00–08:00) are the user's own nights (Spec 1b). Called on app open,
/// sign-in and resume; sends only when the zone changed since this user's
/// last report on this phone. Never throws: a missed report only means the
/// server keeps the last zone it knew, or falls back.
class UserTimezoneReporter {
  UserTimezoneReporter({
    required Future<String> Function() deviceTimezone,
    required Future<void> Function(String timezone) send,
  }) : _deviceTimezone = deviceTimezone,
       _send = send;

  final Future<String> Function() _deviceTimezone;
  final Future<void> Function(String timezone) _send;

  static String prefsKey(String userId) => 'user_timezone_reported:$userId';

  Future<void> report(String? userId) async {
    if (userId == null) return;
    try {
      final zone = await _deviceTimezone();
      if (zone.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(prefsKey(userId)) == zone) return;
      await _send(zone);
      await prefs.setString(prefsKey(userId), zone);
    } catch (_) {
      // Retried on the next open or resume.
    }
  }
}

final userTimezoneReporterProvider = Provider<UserTimezoneReporter>((ref) {
  return UserTimezoneReporter(
    // Read the platform directly on every report: TimezoneUtils caches the
    // zone for the whole process (a traveller's new zone must be seen on
    // resume), returns 'UTC' on any failure (which would overwrite a good
    // zone) and an abbreviation on web. '' means "unknown, send nothing".
    deviceTimezone: () async {
      if (kIsWeb) return '';
      try {
        return await FlutterTimezone.getLocalTimezone();
      } catch (_) {
        return '';
      }
    },
    send: (zone) async {
      await Supabase.instance.client.rpc(
        'set_my_timezone',
        params: {'p_timezone': zone},
      );
    },
  );
});
