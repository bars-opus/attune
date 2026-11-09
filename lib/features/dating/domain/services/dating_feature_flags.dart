import 'package:supabase_flutter/supabase_flutter.dart';

class DatingFeatureFlags {
  static const String datingModeEnabled = 'dating_mode_enabled';
  static const String candidateGeneration = 'dating_candidate_generation';
  static const String matchMessaging = 'dating_match_messaging';
  static const String profilePhotos = 'dating_profile_photos';

  // These `dating_*` keys are authored and read server-side only (RLS hides
  // them from clients, DATING-H1). Listed as the canonical names; the client
  // never reads their values.

  /// Whether Dating is available to this client (Spec 2 W3a, I-4): from
  /// get_dating_home(), which answers `feature_unavailable` when the switch
  /// is off. Any error or unexpected shape is false.
  static Future<bool> isDatingModeAvailable(SupabaseClient supabase) async {
    try {
      final result = await supabase.rpc('get_dating_home');
      if (result is! Map) return false;
      final state = result['state'];
      return state is String && state != 'feature_unavailable';
    } catch (_) {
      return false;
    }
  }
}
