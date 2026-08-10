// Add to lib/features/pulse/providers/pulse_providers.dart

import 'package:attune/features/auth/providers/auth_provider.dart'
    show authStateProvider;
import 'package:attune/features/pulse/data/models/pulse_score.dart';
import 'package:attune/features/pulse/data/repositories/pulse_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final pulseRepositoryProvider = Provider<PulseRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return PulseRepository(supabase);
});

// Current user ID — derives from authStateProvider (auth_provider.dart), NOT
// an imperative supabase.auth.currentUser read: see opinion_providers.dart's
// currentUserIdProvider for the full writeup of the caching bug this fixes.
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.id;
});

// Current relationship ID. ref.watch on currentUserIdProvider (not read) so
// a sign-in/sign-out correctly re-fetches which relationship is active,
// instead of freezing at whatever was true the first time this was
// evaluated.
final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = ref.watch(currentUserIdProvider);
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

// Submit weekly check-in
final submitWeeklyCheckinProvider = FutureProvider.family<
  void,
  ({
    int communicationRating,
    int connectionRating,
    int? conflictHealthRating,
    bool conflictHealthNA,
    int alignmentRating,
    int safetyRating,
  })
>((ref, params) async {
  final repository = ref.read(pulseRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);

  if (userId == null) throw Exception('Not authenticated');
  if (relationshipId == null) throw Exception('No active relationship');

  final weekEnding = _getWeekEnding(DateTime.now());

  await repository.submitCheckin(
    userId: userId,
    relationshipId: relationshipId,
    weekEnding: weekEnding,
    communicationRating: params.communicationRating,
    connectionRating: params.connectionRating,
    conflictHealthRating: params.conflictHealthRating,
    conflictHealthNA: params.conflictHealthNA,
    alignmentRating: params.alignmentRating,
    safetyRating: params.safetyRating,
  );

  // After submission, check if both partners have completed
  final bothCompleted = await repository.haveBothCompletedCheckin(
    relationshipId: relationshipId,
    weekEnding: weekEnding,
  );

  if (bothCompleted) {
    // Trigger immediate pulse recompute
    await repository.triggerPulseRecompute(relationshipId);
  }
});

DateTime _getWeekEnding(DateTime date) {
  // Get the Sunday of the current week
  final daysToSunday = DateTime.sunday - date.weekday;
  return date.add(Duration(days: daysToSunday));
}

// Track last recompute time per relationship
final _lastRecomputeTimeProvider = StateProvider<Map<String, DateTime>>(
  (ref) => {},
);

// On-demand pulse recompute (rate limited to once per 24 hours)
final recomputePulseProvider = FutureProvider.family<bool, String>((
  ref,
  relationshipId,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final lastRecomputeMap = ref.read(_lastRecomputeTimeProvider);
  const rateLimitHours = 24;

  // Check rate limit
  final lastRecompute = lastRecomputeMap[relationshipId];
  if (lastRecompute != null) {
    final hoursSince = DateTime.now().difference(lastRecompute).inHours;
    if (hoursSince < rateLimitHours) {
      throw Exception(
        'Rate limited. You can refresh again in ${rateLimitHours - hoursSince} hours.',
      );
    }
  }

  // Update last recompute time
  ref.read(_lastRecomputeTimeProvider.notifier).state = {
    ...lastRecomputeMap,
    relationshipId: DateTime.now(),
  };

  // Call edge function
  final response = await supabase.functions.invoke(
    'compute-pulse',
    body: {'relationship_id': relationshipId, 'force_recompute': true},
  );

  // Invalidate pulse score providers
  ref.invalidate(currentPulseScoreProvider);
  ref.invalidate(pulseHistoryProvider);

  return true;
});

// Get current pulse score
final currentPulseScoreProvider = FutureProvider<PulseScore?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return null;

  // Get most recent pulse score
  final response =
      await supabase
          .from('pulse_scores')
          .select('*')
          .eq('relationship_id', relationshipId)
          .order('week_ending', ascending: false)
          .limit(1)
          .maybeSingle();

  if (response == null) return null;

  return PulseScore.fromJson(response);
});

// Get pulse history (last 4 weeks for trend chart)
final pulseHistoryProvider = FutureProvider<List<PulseScore>>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return [];

  final response = await supabase
      .from('pulse_scores')
      .select('*')
      .eq('relationship_id', relationshipId)
      .order('week_ending', ascending: false)
      .limit(4);

  return response.map((json) => PulseScore.fromJson(json)).toList();
});
