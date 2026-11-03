import 'dart:async';

import 'package:attune/core/flags/signed_in_flow_flags.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Batch-1 review #3: the stored shape lives in core (sign-out keeps its
// key); re-exported so every import of this file still sees it.
export 'package:attune/core/flags/signed_in_flow_flags.dart';

/// The one network read, so tests can replace it.
abstract class FlowFlagsGateway {
  Future<SignedInFlowFlags> fetch();
}

class SupabaseFlowFlagsGateway implements FlowFlagsGateway {
  static const timeout = Duration(seconds: 10);

  @override
  Future<SignedInFlowFlags> fetch() async {
    final rows = await Supabase.instance.client
        .from('feature_flags')
        .select('key, enabled')
        .inFilter('key', const [
          'flow_paths_v2',
          'flow_couples_v2',
          'couple_profile',
        ])
        .timeout(timeout);
    bool on(String key) =>
        rows.any((row) => row['key'] == key && row['enabled'] == true);
    return SignedInFlowFlags(
      pathsV2: on('flow_paths_v2'),
      couplesV2: on('flow_couples_v2'),
      coupleProfile: on('couple_profile'),
    );
  }
}

final flowFlagsGatewayProvider = Provider<FlowFlagsGateway>(
  (ref) => SupabaseFlowFlagsGateway(),
);

SignedInFlowFlags? _cached(Ref ref) {
  try {
    return FlowFlagsCache(ref.read(sharedPreferencesProvider)).read();
  } catch (_) {
    // No SharedPreferences in a bare test host.
    return null;
  }
}

/// The live flags. A failed read keeps the cached copy, else both off.
/// Re-read on resume and on a change of user (FeatureFlagRefresher).
final flowFlagsProvider = FutureProvider<SignedInFlowFlags>((ref) async {
  final SignedInFlowFlags flags;
  try {
    flags = await ref.read(flowFlagsGatewayProvider).fetch();
  } catch (error) {
    debugPrint('[flow-flags] read failed: ${error.runtimeType}');
    return _cached(ref) ?? SignedInFlowFlags.off;
  }
  unawaited(() async {
    try {
      await FlowFlagsCache(ref.read(sharedPreferencesProvider)).write(flags);
    } catch (error) {
      debugPrint('[flow-flags] cache write failed: ${error.runtimeType}');
    }
  }());
  return flags;
});

SignedInFlowFlags _current(Ref ref) =>
    ref.watch(flowFlagsProvider).valueOrNull ??
    _cached(ref) ??
    SignedInFlowFlags.off;

/// flow_paths_v2, effective: the flag and flow_signin_v2 (spec §2.5 A-6).
/// Before the first answer: the cached copy, else off.
final flowPathsV2Provider = Provider<bool>((ref) {
  if (!ref.watch(signInFlowV2Provider)) return false;
  return _current(ref).pathsV2;
});

/// flow_couples_v2, effective: the flag and flow_paths_v2.
final flowCouplesV2Provider = Provider<bool>((ref) {
  if (!ref.watch(flowPathsV2Provider)) return false;
  return _current(ref).couplesV2;
});

/// couple_profile, effective: the flag and flow_couples_v2 (spec §2.5 A-6,
/// §5.3). Spec 1 W5: About us.
final coupleProfileEnabledProvider = Provider<bool>((ref) {
  if (!ref.watch(flowCouplesV2Provider)) return false;
  return _current(ref).coupleProfile;
});

/// Batch-5 review I-1 (D9): the signed-in flags are known, from an answer
/// this phone has had (this run's, whose cache write SharedPreferences
/// holds in memory at once, or a cached one); a failed read is unknown.
/// Unknown is not off: until then nothing accepts a stored invite.
/// flow_paths_v2 on comes only from such an answer.
///
/// Task 6 re-review R-1: with flow_signin_v2 off they can turn nothing on
/// (flow_paths_v2 needs it), so they are known at once and today's legacy
/// flow runs unchanged, offline included.
final flowFlagsKnownProvider = Provider<bool>((ref) {
  if (!ref.watch(signInFlowV2Provider)) return true;
  if (ref.watch(flowPathsV2Provider)) return true;
  ref.watch(flowFlagsProvider);
  return _cached(ref) != null;
});

/// The live flow_paths_v2, once read (bounded): for code that decides
/// once, such as the automatic push ask, and must not act on a stale
/// first-frame value.
Future<bool> readFlowPathsV2(
  Ref ref, {
  Duration bound = const Duration(seconds: 3),
}) async {
  try {
    if (!ref.read(signInFlowV2Provider)) return false;
    final flags = await ref.read(flowFlagsProvider.future).timeout(bound);
    return flags.pathsV2;
  } catch (_) {
    return ref.read(flowPathsV2Provider);
  }
}
