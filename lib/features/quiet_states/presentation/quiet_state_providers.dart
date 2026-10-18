import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/quiet_states/data/quiet_state_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final quietStatesEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    return await ChatFeatureFlags.isEnabled(
      Supabase.instance.client,
      ChatFeatureFlags.quietStates,
    );
  } catch (_) {
    return false;
  }
});

/// The person's own quiet state, or null when there is none (or the feature
/// is off). Re-read whenever a screen that uses it opens again.
final quietStateProvider = FutureProvider.autoDispose<QuietState?>((ref) async {
  if (!await ref.watch(quietStatesEnabledProvider.future)) return null;
  return ref.read(quietStateServiceProvider).mine();
});

/// Whether celebratory surfaces stay still. While the state is loading, or
/// cannot be read, it counts as quiet: nothing celebrates before we know
/// (plan review M2). With the feature off the state is null, so not quiet.
final isQuietProvider = Provider.autoDispose<bool>((ref) {
  return ref
      .watch(quietStateProvider)
      .when(
        data: (s) => s != null,
        loading: () => true,
        error: (_, __) => true,
      );
});
