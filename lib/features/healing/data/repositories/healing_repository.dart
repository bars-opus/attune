import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HealingRepository {
  HealingRepository(this._supabase);

  final SupabaseClient _supabase;

  /// Every RPC and PostgREST call in this repository is bounded by this.
  ///
  /// Checklist 1.2: without it a stalled connection leaves the caller
  /// awaiting forever, which in practice is a dating or healing screen
  /// spinning with no error and no way back. Matches the 30s used by
  /// RelationshipLifecycleService.
  static const _timeout = Duration(seconds: 30);

  Future<HealingJourney?> getLatestJourney() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

    final response = await _supabase
        .from('healing_journeys')
        .select('*')
        .eq('user_id', userId)
        .inFilter('status', [
          'active',
          'paused',
          'completed',
          'eligible_for_dating_opt_in',
        ])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(_timeout);

    if (response == null) {
      return null;
    }

    return HealingJourney.fromJson(response);
  }

  Future<Map<String, dynamic>?> getStartableRelationship() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

    return await _supabase
        .from('relationships')
        .select('id, ended_at')
        .or('user_a.eq.$userId,user_b.eq.$userId')
        .eq('status', 'ended')
        .order('ended_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(_timeout);
  }

  Future<bool> hasActiveSoloJourney() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return false;
    }

    final response = await _supabase
        .from('healing_journeys')
        .select('id')
        .eq('user_id', userId)
        .isFilter('relationship_id', null)
        .inFilter('status', ['active', 'paused'])
        .maybeSingle()
        .timeout(_timeout);

    return hasActiveSoloJourneyFromResponse(response);
  }

  Future<HealingJourney> getOrCreateJourney({
    String? relationshipId,
    required DateTime breakupAt,
    required String breakupAtSource,
  }) async {
    final journeyId = await _supabase
        .rpc(
          'get_or_create_healing_journey',
          params: {
            'p_relationship_id': relationshipId,
            'p_breakup_at': breakupAt.toUtc().toIso8601String(),
            'p_breakup_at_source': breakupAtSource,
          },
        )
        .timeout(_timeout);

    return getJourney(journeyId as String);
  }

  Future<HealingJourney> getJourney(String journeyId) async {
    final response = await _supabase
        .from('healing_journeys')
        .select('*')
        .eq('id', journeyId)
        .single()
        .timeout(_timeout);

    return HealingJourney.fromJson(response);
  }

  Future<void> updateReflection({
    required String journeyId,
    required Map<String, dynamic> answers,
  }) async {
    await _supabase
        .rpc(
          'save_healing_reflection',
          params: {'p_journey_id': journeyId, 'p_answers': answers},
        )
        .timeout(_timeout);
  }

  Future<void> completeReflection(String journeyId) async {
    await _supabase
        .rpc('complete_healing_reflection', params: {'p_journey_id': journeyId})
        .timeout(_timeout);
  }

  Future<void> completePostMortem({
    required String journeyId,
    required String status,
    String? observation,
    String? confidence,
    String? reflectionPrompt,
  }) async {
    await _supabase
        .rpc(
          'complete_healing_generated_stage',
          params: {
            'p_journey_id': journeyId,
            'p_stage': 'post_mortem',
            'p_status': status,
            'p_observation': observation,
            'p_confidence': confidence,
            'p_reflection_prompt': reflectionPrompt,
            'p_portrait': null,
            'p_portrait_reflection': null,
          },
        )
        .timeout(_timeout);
  }

  Future<void> completePatternAwareness(String journeyId) async {
    await _supabase
        .rpc(
          'complete_healing_pattern_awareness',
          params: {'p_journey_id': journeyId},
        )
        .timeout(_timeout);
  }

  Future<void> completePortrait({
    required String journeyId,
    required String status,
    String? portraitText,
    String? portraitReflection,
    String? reflectionPrompt,
  }) async {
    await _supabase
        .rpc(
          'complete_healing_generated_stage',
          params: {
            'p_journey_id': journeyId,
            'p_stage': 'portrait',
            'p_status': status,
            'p_observation': null,
            'p_confidence': null,
            'p_reflection_prompt': reflectionPrompt,
            'p_portrait': portraitText,
            'p_portrait_reflection': portraitReflection,
          },
        )
        .timeout(_timeout);
  }

  Future<Map<String, dynamic>> submitReadiness({
    required String journeyId,
    required Map<String, dynamic> answers,
  }) async {
    final response = await _supabase
        .rpc(
          'submit_healing_readiness',
          params: {'p_journey_id': journeyId, 'p_answers': answers},
        )
        .timeout(_timeout);

    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> completeReadinessWithoutScore(String journeyId) async {
    await _supabase
        .rpc(
          'complete_healing_readiness_without_score',
          params: {'p_journey_id': journeyId},
        )
        .timeout(_timeout);
  }

  Future<Map<String, dynamic>?> getLatestReadinessAttempt(
    String journeyId,
  ) async {
    final response = await _supabase
        .rpc(
          'get_latest_healing_readiness_attempt',
          params: {'p_journey_id': journeyId},
        )
        .timeout(_timeout);

    if (response == null) {
      return null;
    }

    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> archiveJourney(String journeyId) async {
    await _supabase
        .rpc('archive_healing_journey', params: {'p_journey_id': journeyId})
        .timeout(_timeout);
  }

  Future<void> deleteJourney(String journeyId) async {
    await _supabase
        .rpc('delete_healing_journey', params: {'p_journey_id': journeyId})
        .timeout(_timeout);
  }
}

/// Pure decision logic for [HealingRepository.hasActiveSoloJourney] —
/// separated out so it's unit-testable without mocking Supabase's
/// PostgrestFilterBuilder chain, which returns a new builder instance
/// per chained call rather than mutating `this`.
bool hasActiveSoloJourneyFromResponse(Map<String, dynamic>? response) {
  return response != null;
}
