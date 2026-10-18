import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The feature flags manual topics depend on that are on right now. An
/// unreadable flag counts as off, so a topic never describes a feature the
/// person cannot find. Re-read on resume with the app's other flags
/// (FeatureFlagRefresher).
final documentationFlagsProvider = FutureProvider<Set<String>>((ref) async {
  final enabled = <String>{};
  try {
    final client = Supabase.instance.client;
    for (final flag in DocumentationRegistry.allRequiredFlags) {
      if (await ChatFeatureFlags.isEnabled(client, flag)) enabled.add(flag);
    }
  } catch (_) {
    return const <String>{};
  }
  return enabled;
});
