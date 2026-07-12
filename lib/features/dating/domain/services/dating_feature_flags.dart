import 'package:supabase_flutter/supabase_flutter.dart';

class DatingFeatureFlags {
  static const String datingModeEnabled = 'dating_mode_enabled';
  static const String alignmentAlgorithmV1 = 'dating_alignment_algorithm_v1';
  static const String candidateGeneration = 'dating_candidate_generation';
  static const String matchMessaging = 'dating_match_messaging';
  static const String profilePhotos = 'dating_profile_photos';

  // These `dating_*` keys are authored and read server-side only (RLS hides them
  // from clients per DATING-H1). Listed here as the canonical flag set; the
  // client never reads their values directly — see isDatingModeAvailable.

  /// Whether Dating Mode is available to this client.
  ///
  /// DATING-H1: the client no longer reads `feature_flags` directly (that table
  /// is server-only for `dating_*` keys, so the rollout plan isn't exposed and
  /// the gate isn't spoofable). Availability is derived from the server-authored
  /// `get_dating_eligibility()` RPC, which returns reason='feature_unavailable'
  /// when the flag is off. Any error or unexpected shape fails safe to false.
  static Future<bool> isDatingModeAvailable(SupabaseClient supabase) async {
    try {
      final result = await supabase.rpc('get_dating_eligibility');
      if (result is! Map) return false;
      // Off only when the server explicitly says the feature is unavailable;
      // every other reason (account/relationship/healing gates) means the flag
      // itself is ON and the dashboard should render its gated state.
      return result['reason'] != 'feature_unavailable';
    } catch (_) {
      return false;
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
