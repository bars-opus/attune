import 'package:supabase_flutter/supabase_flutter.dart';

class HealingGenerationService {
  HealingGenerationService({required SupabaseClient supabase})
    : _supabase = supabase;

  final SupabaseClient _supabase;

  Future<Map<String, dynamic>?> generatePostMortem({
    required String journeyId,
  }) async {
    final response = await _supabase.functions.invoke(
      'generate-healing-post-mortem',
      body: {'journey_id': journeyId},
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      return null;
    }

    return data;
  }

  Future<Map<String, dynamic>?> generatePortrait({
    required String journeyId,
  }) async {
    final response = await _supabase.functions.invoke(
      'generate-healing-portrait',
      body: {'journey_id': journeyId},
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      return null;
    }

    return data;
  }
}
