// lib/features/pulse/domain/pulse_refresh_copy.dart
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

/// What the Pulse screen says when a refresh fails. The server enforces the
/// 24 h limit (429 with `retry_after_seconds`); nothing else about the error
/// is ever shown.
String pulseRefreshMessage(Object error) {
  if (error is FunctionException && error.status == 429) {
    final details = error.details;
    final seconds =
        details is Map
            ? (details['retry_after_seconds'] as num?)?.toInt()
            : null;
    final s = seconds ?? 86400;
    if (s <= 3600) return 'You can refresh again in under an hour.';
    return 'You can refresh again in about ${(s / 3600).ceil()} hours.';
  }
  return "Couldn't refresh Pulse. Try again.";
}
