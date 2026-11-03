import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The signed-in Spec 1 flags (spec §2.5, §5.3), as stored:
/// `flow_paths_v2`, `flow_couples_v2` and (W5) `couple_profile`. The providers in
/// features/onboarding/presentation/providers/flow_flags.dart turn them
/// into the effective value (the flag and everything it needs). Here, in
/// core, so sign-out's keep set can name the cache key without importing
/// the router graph.
@immutable
class SignedInFlowFlags {
  const SignedInFlowFlags({
    required this.pathsV2,
    required this.couplesV2,
    this.coupleProfile = false,
  });

  /// What an unreadable flag means: off.
  static const off = SignedInFlowFlags(pathsV2: false, couplesV2: false);

  final bool pathsV2;
  final bool couplesV2;

  /// Spec 1 W5: About us.
  final bool coupleProfile;

  @override
  bool operator ==(Object other) =>
      other is SignedInFlowFlags &&
      other.pathsV2 == pathsV2 &&
      other.couplesV2 == couplesV2 &&
      other.coupleProfile == coupleProfile;

  @override
  int get hashCode => Object.hash(pathsV2, couplesV2, coupleProfile);
}

/// The last answer, for the first frame of the next launch. Neutral key
/// names (D20).
class FlowFlagsCache {
  const FlowFlagsCache(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'attune.flags.signed_in.v1';

  SignedInFlowFlags? read() {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return SignedInFlowFlags(
        pathsV2: json['paths'] == true,
        couplesV2: json['couples'] == true,
        coupleProfile: json['couple_profile'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(SignedInFlowFlags flags) => _prefs.setString(
    key,
    jsonEncode({
      'paths': flags.pathsV2,
      'couples': flags.couplesV2,
      // Spec 1 W5: written only when on, so the W3 shape is unchanged
      // while it is off (an absent key reads as off).
      if (flags.coupleProfile) 'couple_profile': true,
    }),
  );
}
