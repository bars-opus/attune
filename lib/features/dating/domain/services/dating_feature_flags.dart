import 'package:supabase_flutter/supabase_flutter.dart';

class DatingFeatureFlags {
  static const String datingModeEnabled = 'dating_mode_enabled';
  static const String alignmentAlgorithmV1 = 'dating_alignment_algorithm_v1';
  static const String candidateGeneration = 'dating_candidate_generation';
  static const String matchMessaging = 'dating_match_messaging';
  static const String profilePhotos = 'dating_profile_photos';

  static const Map<String, bool> _safeDefaults = <String, bool>{
    datingModeEnabled: false,
    alignmentAlgorithmV1: false,
    candidateGeneration: false,
    matchMessaging: false,
    profilePhotos: false,
  };

  static Future<bool> isEnabled(
    SupabaseClient supabase,
    String flagName,
  ) async {
    final safeDefault = _safeDefaults[flagName] ?? false;
    try {
      final row =
          await supabase
              .from('feature_flags')
              .select('enabled')
              .eq('key', flagName)
              .maybeSingle();
      return row == null ? safeDefault : row['enabled'] == true;
    } catch (_) {
      return safeDefault;
    }
  }
}

class DatingMonitoring {
  const DatingMonitoring._();

  // Product telemetry must stay aggregate and content-free. The production
  // adapter can map these coarse counters to the approved monitoring backend.
  static void recordOperationalCounter(String approvedCounterName) {
    const allowed = <String>{
      'candidate_generation_completed',
      'candidate_generation_failed',
      'interest_action_completed',
      'mutual_match_created',
      'authorization_denied',
    };
    if (!allowed.contains(approvedCounterName)) return;
  }
}
