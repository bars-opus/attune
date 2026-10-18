import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Spec 8 (research 06 F14): a private safety check, per relationship. The
/// answers go to the server and are never stored or shown back; the server
/// says which card to show at that moment and nothing else.
const safetySelfCheckRowTitle = 'A private check-in about how safe you feel';

/// Offered again after 90 days (or never answered). The row reads the same
/// either way (plan review I1).
bool safetySelfCheckDue(DateTime? answeredAt, DateTime now) =>
    answeredAt == null || now.difference(answeredAt) > const Duration(days: 90);

class SafetySelfCheckService {
  SupabaseClient get _client => Supabase.instance.client;

  /// 'resources', 'plain' or 'none'.
  Future<String> submit(
    String relationshipId,
    Map<String, String> answers,
  ) async {
    final res = await _client.rpc(
      'submit_my_safety_check',
      params: {'p_relationship_id': relationshipId, 'p_answers': answers},
    );
    return (res is Map ? res['card'] as String? : null) ?? 'none';
  }

  /// When this was last answered, or null.
  Future<DateTime?> answeredAt(String relationshipId) async {
    final rows =
        await _client.rpc(
              'get_my_safety_check',
              params: {'p_relationship_id': relationshipId},
            )
            as List<dynamic>?;
    if (rows == null || rows.isEmpty) return null;
    return DateTime.tryParse(
      (rows.first as Map)['answered_at'] as String? ?? '',
    );
  }
}

final safetySelfCheckServiceProvider = Provider<SafetySelfCheckService>(
  (_) => SafetySelfCheckService(),
);

final safetySelfCheckEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    return await ChatFeatureFlags.isEnabled(
      Supabase.instance.client,
      ChatFeatureFlags.privateSafetyCheck,
    );
  } catch (_) {
    return false;
  }
});
