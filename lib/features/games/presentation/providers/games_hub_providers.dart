// lib/features/games/presentation/providers/games_hub_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

// Current user ID
final currentUserIdProvider = Provider<String?>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return supabase.auth.currentUser?.id;
});

// Current relationship ID
final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final response = await supabase
      .from('relationships')
      .select('id')
      .or('user_a.eq.$userId,user_b.eq.$userId')
      .eq('status', 'active')
      .maybeSingle();

  return response?['id'] as String?;
});

// Active games for current relationship
final activeGamesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return [];

  final response = await supabase
      .from('game_sessions')
      .select('*')
      .eq('relationship_id', relationshipId)
      .inFilter('status', ['invited', 'active'])
      .order('created_at', ascending: false);

  // Transform to display format
  return response.map((json) {
    final gameType = json['game_type'] as String;
    String displayName;
    switch (gameType) {
      case 'this_or_that': displayName = 'This or That'; break;
      case 'truth_or_dare': displayName = 'Truth or Dare'; break;
      case '36_questions': displayName = '36 Questions'; break;
      default: displayName = gameType;
    }
    return {
      ...json,
      'game_type_display': displayName,
    };
  }).toList();
});

// Recent completed games
final recentGamesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return [];

  final response = await supabase
      .from('game_sessions')
      .select('*')
      .eq('relationship_id', relationshipId)
      .eq('status', 'completed')
      .order('completed_at', ascending: false)
      .limit(3);

  return response;
});
