// lib/features/games/presentation/providers/games_hub_providers.dart

import 'dart:async';

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

  final response =
      await supabase
          .from('relationships')
          .select('id')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .eq('status', 'active')
          .maybeSingle();

  return response?['id'] as String?;
});

// Active games for current relationship
/// Keeps the hub live while it is on screen.
///
/// activeGamesProvider was a plain FutureProvider read once in initState,
/// so an invite arriving while the partner was LOOKING at the hub never
/// appeared — and neither did the other side accepting or finishing a
/// game. They had to navigate away and back.
///
/// PostgresChangeEvent.all rather than inserts alone: an INSERT is a new
/// invite, an UPDATE is the partner accepting or a game completing, and
/// the hub shows both lists.
final gameSessionEventsProvider = StreamProvider<void>((ref) async* {
  final relationshipId = await ref.watch(currentRelationshipIdProvider.future);
  if (relationshipId == null) return;

  final supabase = ref.read(supabaseClientProvider);
  final controller = StreamController<void>.broadcast();

  final channel =
      supabase
          .channel('games:$relationshipId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'game_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'relationship_id',
              value: relationshipId,
            ),
            callback: (_) {
              // The lists are refetched rather than patched from the payload:
              // activeGamesProvider filters by status and orders by date, and
              // reproducing that here would be a second, drifting copy of the
              // same query.
              ref.invalidate(activeGamesProvider);
              ref.invalidate(recentGamesProvider);
              if (!controller.isClosed) controller.add(null);
            },
          )
          .subscribe();

  // A channel outliving its provider leaks a socket subscription for the
  // rest of the session.
  ref.onDispose(() {
    unawaited(controller.close());
    unawaited(supabase.removeChannel(channel));
  });

  yield* controller.stream;
});

/// The human name for a game_type.
///
/// The hub's own switch named only three types and fell through to the RAW
/// value for the rest, so a Mirror invite read as "mirror" and a Paint Ball
/// one as "paint_ball" — the partner's only notice that a game is waiting,
/// rendered as a database value.
///
/// Covers every type that can reach game_sessions: the six in
/// game_questions' CHECK constraint, plus 36_questions and paint_ball,
/// which write the table without appearing in it.
///
/// An unknown type title-cases rather than falling back to the raw value,
/// so a type added to the database before the app knows about it still
/// reads as words.
String gameTypeDisplayName(String gameType) {
  const names = {
    'this_or_that': 'This or That',
    'truth_or_dare': 'Truth or Dare',
    '36_questions': '36 Questions',
    'mirror': 'Mirror',
    'sliding_scale': 'Sliding Scale',
    'scenario': 'Scenario',
    'love_map': 'Love Map',
    'paint_ball': 'Paint Ball',
  };

  final known = names[gameType];
  if (known != null) return known;

  return gameType
      .split('_')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

final activeGamesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
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
    return {
      ...json,
      'game_type_display': gameTypeDisplayName(json['game_type'] as String),
    };
  }).toList();
});

// Recent completed games
final recentGamesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
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
