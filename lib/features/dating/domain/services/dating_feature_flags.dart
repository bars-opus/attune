import 'package:supabase_flutter/supabase_flutter.dart';

class DatingFeatureFlags {
  static const String datingModeEnabled = 'dating_mode_enabled';
  static const String candidateGeneration = 'dating_candidate_generation';
  static const String matchMessaging = 'dating_match_messaging';
  static const String profilePhotos = 'dating_profile_photos';

  /// Spec 2 W9 (R-W9-16): Become a couple on Attune and what follows it.
  static const String coupleLink = 'dating_couple_link';

  // These `dating_*` keys are authored and read server-side only (RLS hides
  // them from clients, DATING-H1). Listed as the canonical names; the client
  // never reads their values.

  /// Whether Dating is available to this client (Spec 2 W3a, I-4): from
  /// get_dating_home(), which answers `feature_unavailable` when the switch
  /// is off. Any error or unexpected shape is false.
  static Future<bool> isDatingModeAvailable(SupabaseClient supabase) async =>
      (await flagsOn(supabase)).contains(datingModeEnabled);

  /// Spec 2 W9 (R-W9-16): the Dating flags on for this client, from one
  /// get_dating_home() answer: [datingModeEnabled] unless it answers
  /// `feature_unavailable`, [coupleLink] while it carries `couple_link`.
  /// Any error or unexpected shape is none.
  static Future<Set<String>> flagsOn(SupabaseClient supabase) async {
    try {
      return flagsFrom(await supabase.rpc('get_dating_home'));
    } catch (_) {
      return const <String>{};
    }
  }

  /// [flagsOn]'s reading of one answer.
  static Set<String> flagsFrom(Object? result) {
    if (result is! Map) return const <String>{};
    final state = result['state'];
    return {
      if (state is String && state != 'feature_unavailable') datingModeEnabled,
      if (result['couple_link'] == true) coupleLink,
    };
  }
}
