// Add to lib/features/conflict_translator/domain/services/translator_pattern_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class TranslatorPatternService {
  final SupabaseClient _supabase;

  TranslatorPatternService(this._supabase);

  /// Check if a user has used the translator enough to surface a personal insight
  Future<bool> shouldSurfaceInsight({required String relationshipId}) async {
    final response = await _supabase
        .from('translator_logs')
        .select('id')
        .eq('relationship_id', relationshipId)
        .limit(5);

    return response.length >= 5;
  }

  /// Get the most common core need for a user
  Future<Map<String, dynamic>?> getDominantNeed({
    required String relationshipId,
  }) async {
    final response = await _supabase
        .from('translator_logs')
        .select('core_need_identified')
        .eq('relationship_id', relationshipId)
        .order('used_at', ascending: false)
        .limit(6);

    if (response.isEmpty) return null;

    // Count occurrences of each need
    final Map<String, int> counts = {};
    for (final log in response) {
      final need = log['core_need_identified'] as String?;
      if (need != null) {
        counts[need] = (counts[need] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) return null;

    // Find the most common need
    final dominantNeed = counts.entries.reduce((a, b) => a.value > b.value ? a : b);

    // Map to display text
    final needDisplay = _getNeedDisplay(dominantNeed.key);

    return {
      'core_need': dominantNeed.key,
      'display_text': needDisplay,
      'count': dominantNeed.value,
    };
  }

  String _getNeedDisplay(String need) {
    switch (need) {
      case 'respect': return 'to be heard';
      case 'fairness': return 'to feel fairly treated';
      case 'affection': return 'to feel valued';
      case 'security': return 'to feel safe';
      case 'autonomy': return 'to have space';
      case 'rest': return 'for relief';
      default: return need;
    }
  }

  /// Surface insight to the user
  Future<void> surfaceInsight({
    required String userId,
    required String relationshipId,
  }) async {
    final dominantNeed = await getDominantNeed(relationshipId: relationshipId);
    if (dominantNeed == null) return;

    final insightBody =
        'The underlying need in ${dominantNeed['count']} of your last 6 rewritten messages was '
        '${dominantNeed['display_text']}. This might be worth a direct conversation.';

    await _supabase.from('personal_insights').insert({
      'user_id': userId,
      'relationship_id': relationshipId,
      'insight_type': 'translator_pattern',
      'insight_body': insightBody,
    });
  }

  /// Check if insight has already been surfaced recently
  Future<bool> hasInsightBeenSurfacedRecently({
    required String relationshipId,
    required String userId,
  }) async {
    final response = await _supabase
        .from('personal_insights')
        .select('created_at')
        .eq('user_id', userId)
        .eq('relationship_id', relationshipId)
        .eq('insight_type', 'translator_pattern')
        .gt('created_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String())
        .limit(1);

    return response.isNotEmpty;
  }
}
