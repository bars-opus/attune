// lib/features/pulse/data/repositories/pulse_repository.dart

import 'package:attune/core/notifications/services/attune_notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PulseRepository {
  final SupabaseClient _supabase;
  final AttuneNotificationService _notificationService;

  PulseRepository(this._supabase)
    : _notificationService = AttuneNotificationService();

  Future<void> submitCheckin({
    required String userId,
    required String relationshipId,
    required DateTime weekEnding,
    required int communicationRating,
    required int connectionRating,
    required int? conflictHealthRating,
    required bool conflictHealthNA,
    required int alignmentRating,
    required int safetyRating,
  }) async {
    await _supabase.from('weekly_checkins').upsert({
      'user_id': userId,
      'relationship_id': relationshipId,
      'week_ending': weekEnding.toIso8601String().split('T')[0],
      'communication_rating': communicationRating,
      'connection_rating': connectionRating,
      'conflict_health_rating': conflictHealthRating,
      'conflict_health_na': conflictHealthNA,
      'alignment_rating': alignmentRating,
      'safety_rating': safetyRating,
    }, onConflict: 'user_id,week_ending');
  }

  Future<bool> haveBothCompletedCheckin({
    required String relationshipId,
    required DateTime weekEnding,
  }) async {
    final response = await _supabase
        .from('weekly_checkins')
        .select('user_id')
        .eq('relationship_id', relationshipId)
        .eq('week_ending', weekEnding.toIso8601String().split('T')[0]);

    // Get relationship to find both user IDs
    final relationshipRes =
        await _supabase
            .from('relationships')
            .select('user_a, user_b')
            .eq('id', relationshipId)
            .single();

    final userIds = response.map((r) => r['user_id'] as String).toList();
    final bothUsers = [relationshipRes['user_a'], relationshipRes['user_b']];

    return bothUsers.every((id) => userIds.contains(id));
  }

  Future<void> triggerPulseRecompute(String relationshipId) async {
    try {
      // Supabase throws on function errors in the current SDK surface.
      await _supabase.functions.invoke(
        'compute-pulse',
        body: {'relationship_id': relationshipId, 'force_recompute': true},
      );

      // After pulse is recomputed, send notifications to both partners
      await _sendPulseUpdatedNotifications(relationshipId);
    } catch (e) {
      print('Error recomputing pulse: $e');
    }
  }

  Future<void> _sendPulseUpdatedNotifications(String relationshipId) async {
    try {
      // Get the most recent pulse score
      final pulseResponse =
          await _supabase
              .from('pulse_scores')
              .select('*')
              .eq('relationship_id', relationshipId)
              .order('week_ending', ascending: false)
              .limit(1)
              .single();

      // Get previous pulse for delta
      final previousResponse =
          await _supabase
              .from('pulse_scores')
              .select('overall_score')
              .eq('relationship_id', relationshipId)
              .order('week_ending', ascending: false)
              .limit(1)
              .maybeSingle();

      final newScore = pulseResponse['overall_score'] as int;
      final delta =
          previousResponse != null
              ? newScore - (previousResponse['overall_score'] as int)
              : null;

      // Get relationship members
      final relationshipRes =
          await _supabase
              .from('relationships')
              .select('user_a, user_b')
              .eq('id', relationshipId)
              .single();

      // Send notifications to both partners
      await _notificationService.sendPulseUpdated(
        userId: relationshipRes['user_a'] as String,
        newScore: newScore,
        delta: delta,
      );

      await _notificationService.sendPulseUpdated(
        userId: relationshipRes['user_b'] as String,
        newScore: newScore,
        delta: delta,
      );
    } catch (e) {
      print('Error sending pulse notifications: $e');
    }
  }

  Future<Map<String, dynamic>?> getCurrentPulse(String relationshipId) async {
    final response =
        await _supabase
            .from('pulse_scores')
            .select('*')
            .eq('relationship_id', relationshipId)
            .order('week_ending', ascending: false)
            .limit(1)
            .maybeSingle();

    return response;
  }

  Future<List<Map<String, dynamic>>> getPulseHistory(
    String relationshipId,
  ) async {
    final response = await _supabase
        .from('pulse_scores')
        .select('*')
        .eq('relationship_id', relationshipId)
        .order('week_ending', ascending: false)
        .limit(4);

    return response;
  }
}
