import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The flag key (Spec 1 §2.5).
const opinionsSafetyFlag = 'opinions_safety_v1';

/// opinions_safety_v1, as read (signed in: feature_flags is not readable
/// signed out, so a guest reads off). Re-read on resume with the app's other
/// flags (FeatureFlagRefresher).
final opinionsSafetyReadProvider = FutureProvider<bool>((ref) async {
  try {
    return await ChatFeatureFlags.isEnabled(
      Supabase.instance.client,
      opinionsSafetyFlag,
    );
  } catch (_) {
    return false;
  }
});

/// Spec 1 §5.3 `opinionsSafetyProvider`: the support link and the at-risk
/// reason show only while this is true. Off until the read answers, off when
/// unreadable, so with the flag off Opinions looks exactly as before.
final opinionsSafetyProvider = Provider<bool>(
  (ref) => ref.watch(opinionsSafetyReadProvider).valueOrNull ?? false,
);
