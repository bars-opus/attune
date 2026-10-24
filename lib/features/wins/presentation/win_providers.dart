import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/wins/domain/win_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final winsEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    return await ChatFeatureFlags.isEnabled(
      Supabase.instance.client,
      ChatFeatureFlags.shareAWin,
    );
  } catch (_) {
    return false;
  }
});

/// The partner's recent wins this person has not asked about yet. Read
/// again on each return to Attune (the hub stays mounted behind the cover).
final winCardsProvider = FutureProvider.autoDispose
    .family<List<WinCard>, String>((ref, relationshipId) async {
      refreshWhenVisibleAgain(ref);
      if (!await ref.watch(winsEnabledProvider.future)) return const [];
      return ref.read(togetherRepositoryProvider).listWinCards(relationshipId);
    });
