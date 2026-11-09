import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/domain/services/dating_feature_flags.dart';
import 'package:flutter/widgets.dart';
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
      // R-35: dating_% flags are server-only; Dating's own read answers,
      // on Dating's own client (T12 carry E; W4b's device header).
      final on = flag == DatingFeatureFlags.datingModeEnabled
          ? await DatingFeatureFlags.isDatingModeAvailable(
            ref.read(datingSupabaseClientProvider),
          )
          : await ChatFeatureFlags.isEnabled(client, flag);
      if (on) enabled.add(flag);
    }
  } catch (_) {
    return const <String>{};
  }
  return enabled;
});

/// The flags above as [context]'s ProviderScope holds them now, for a
/// topic's flag-gated passages (B7 ruling M-3). None while loading or with
/// no scope, so a passage about a switched-off feature stays hidden.
Set<String> documentationFlagsOf(BuildContext context) {
  try {
    return ProviderScope.containerOf(
          context,
          listen: false,
        ).read(documentationFlagsProvider).valueOrNull ??
        const <String>{};
  } catch (_) {
    return const <String>{};
  }
}
