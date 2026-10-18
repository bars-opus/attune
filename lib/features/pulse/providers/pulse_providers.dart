// lib/features/pulse/providers/pulse_providers.dart

import 'package:attune/features/auth/providers/auth_provider.dart'
    show authStateProvider;
import 'package:attune/features/pulse/data/models/pulse_score.dart';
import 'package:attune/features/pulse/data/models/your_week.dart';
import 'package:attune/features/pulse/data/repositories/pulse_repository.dart';
import 'package:attune/features/pulse/domain/pulse_week.dart';
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

// Current ACTIVE relationship ID (null while paused). ref.watch on
// currentUserIdProvider so a sign-in/sign-out re-fetches.
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

typedef PulseRelationship = ({String id, String status});

/// The current relationship with its status. Unlike
/// [currentRelationshipIdProvider] it keeps 'paused' visible, so Pulse can
/// hide itself (F5 (5)) instead of showing a brand-new no-data state.
final currentRelationshipStatusProvider = FutureProvider<PulseRelationship?>((
  ref,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final row =
      await supabase
          .from('relationships')
          .select('id,status')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .inFilter('status', ['active', 'paused'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
  if (row == null) return null;
  return (id: row['id'] as String, status: row['status'] as String);
});

/// The one call to the compute-pulse edge function. `force: true` asks the
/// server to rewrite this week's shared row (and claims the caller's 24 h
/// limit); `force: false` only refreshes my private pass. A Provider so a
/// widget test can replace it without a Supabase client.
typedef PulseRecomputeInvoker =
    Future<void> Function(String relationshipId, {required bool force});

final pulseRecomputeInvokerProvider = Provider<PulseRecomputeInvoker>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return (relationshipId, {required force}) async {
    await supabase.functions.invoke(
      'compute-pulse',
      body: {'relationship_id': relationshipId, 'force_recompute': force},
    );
  };
});

// Submit weekly check-in. Private since Spec 1a: it feeds "Your week" and
// nothing shared. The non-forced call asks the server for the private pass
// only (no claim, no shared rewrite) so "Your week" fills in even when the
// weekly cron is off.
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

  await repository.submitCheckin(
    userId: userId,
    relationshipId: relationshipId,
    weekEnding: pulseWeekEnding(DateTime.now()),
    communicationRating: params.communicationRating,
    connectionRating: params.connectionRating,
    conflictHealthRating: params.conflictHealthRating,
    conflictHealthNA: params.conflictHealthNA,
    alignmentRating: params.alignmentRating,
    safetyRating: params.safetyRating,
  );

  // Best effort: the answers are saved either way; a failed private pass
  // just leaves "Your week" showing a dash until the next refresh.
  try {
    await ref.read(pulseRecomputeInvokerProvider)(relationshipId, force: false);
  } catch (_) {}

  // After the awaits, so this never runs during the provider's own
  // initialization (see recomputePulseProvider's note below).
  ref.invalidate(yourWeekProvider);
});

// On-demand pulse recompute. The 24 h limit is enforced by the server
// (claim_pulse_recompute): a refusal arrives as a FunctionException with
// status 429 and `retry_after_seconds`, rethrown for the screen to word
// (pulseRefreshMessage). No client-side bookkeeping — it reset on restart
// and protected nothing. autoDispose, and the screen invalidates it before
// each read: a FutureProvider caches its result, and a second tap served
// from cache would never reach the server (Review Focus 8).
final recomputePulseProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  relationshipId,
) async {
  await ref.read(pulseRecomputeInvokerProvider)(relationshipId, force: true);

  // Deferred until after the await above — Riverpod treats a provider's
  // synchronous pre-await code as still part of its own initialization,
  // and mutating another provider's state in that window trips "Providers
  // are not allowed to modify other providers during their initialization".
  ref.invalidate(currentPulseScoreProvider);
  ref.invalidate(pulseHistoryProvider);
  ref.invalidate(yourWeekProvider);

  return true;
});

// Get current pulse score
final currentPulseScoreProvider = FutureProvider<PulseScore?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return null;

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

/// My private "Your week": own check-in for the current week plus my latest
/// private Emotional safety. Self-only by RLS.
final yourWeekProvider = FutureProvider<YourWeek>((ref) async {
  final repository = ref.read(pulseRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const YourWeek();
  return repository.fetchYourWeek(
    userId: userId,
    weekEndingKey: pulseWeekEndingKey(DateTime.now()),
  );
});
