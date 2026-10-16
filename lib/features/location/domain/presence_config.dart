// lib/features/location/domain/presence_config.dart
/// The couple map's numbers (spec §9 / checklist 4.11). Mirrors SQL presence_config().
abstract final class PresenceConfig {
  static const fadingAfter = Duration(hours: 4);
  static const staleAfter = Duration(hours: 8);
  static const maxPause = Duration(hours: 8);
  static const refreshEvery = Duration(minutes: 15);
  static const fixTimeout = Duration(seconds: 20);
  static const geocodeTimeout = Duration(seconds: 10);

  /// Client-side debounce of automatic samples; mirrors SQL rate_limit_s.
  static const recordDebounce = Duration(seconds: 60);
}
