// lib/features/pulse/data/repositories/pulse_repository.dart

import 'package:attune/features/pulse/data/models/your_week.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PulseRepository {
  final SupabaseClient _supabase;

  PulseRepository(this._supabase);

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

  /// My own check-in and my private Emotional safety, both for
  /// [weekEndingKey]. Both tables are auth.uid()-only on the server, so this
  /// can never read the partner's rows (Spec 1a).
  ///
  /// The former haveBothCompletedCheckin / triggerPulseRecompute /
  /// notification paths are gone: RLS made the first always false, and no
  /// shared number moves on a check-in any more.
  Future<YourWeek> fetchYourWeek({
    required String userId,
    required String weekEndingKey,
  }) async {
    final checkinRow =
        await _supabase
            .from('weekly_checkins')
            .select(
              'communication_rating,connection_rating,conflict_health_rating,'
              'conflict_health_na,alignment_rating,safety_rating',
            )
            .eq('user_id', userId)
            .eq('week_ending', weekEndingKey)
            .maybeSingle();
    // This week only: last week's private score must not read as this
    // week's (I5).
    final scoreRow =
        await _supabase
            .from('pulse_private_scores')
            .select('emotional_safety,week_ending')
            .eq('user_id', userId)
            .eq('week_ending', weekEndingKey)
            .maybeSingle();
    return YourWeek(
      checkin:
          checkinRow == null ? null : WeeklyCheckinAnswers.fromJson(checkinRow),
      emotionalSafety: (scoreRow?['emotional_safety'] as num?)?.toInt(),
      weekEnding:
          scoreRow == null
              ? null
              : DateTime.parse(scoreRow['week_ending'] as String),
    );
  }
}
