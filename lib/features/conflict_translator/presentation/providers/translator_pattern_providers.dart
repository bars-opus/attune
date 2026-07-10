// Add to lib/features/conflict_translator/presentation/providers/translator_pattern_providers.dart

import 'package:attune/core/moderation/presentation/providers/moderation_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/services/translator_pattern_service.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final translatorPatternServiceProvider = Provider<TranslatorPatternService>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return TranslatorPatternService(supabase);
});

final shouldSurfaceTranslatorInsightProvider = FutureProvider.family<bool, String>((ref, relationshipId) async {
  final service = ref.read(translatorPatternServiceProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) return false;

  // Check if already surfaced recently
  final alreadySurfaced = await service.hasInsightBeenSurfacedRecently(
    relationshipId: relationshipId,
    userId: userId,
  );

  if (alreadySurfaced) return false;

  return await service.shouldSurfaceInsight(relationshipId: relationshipId);
});

final translatorInsightProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, relationshipId) async {
  final service = ref.read(translatorPatternServiceProvider);
  return await service.getDominantNeed(relationshipId: relationshipId);
});
