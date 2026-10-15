// lib/features/timeline/data/repositories/timeline_repository.dart

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/timeline_event_model.dart';

class TimelineRepository {
  final SupabaseClient _supabase;

  /// Partner pushes for new moments are sent by the database
  /// (trigger notify_partner_moment_logged), not from here.
  TimelineRepository(this._supabase);

  /// Create a new timeline event
  Future<TimelineEventModel> createEvent({
    required String relationshipId,
    required String loggedBy,
    required String eventType,
    required String title,
    required DateTime occurredAt,
    String? note,
    int? moodScore,
    String visibility = 'shared',
  }) async {
    final response =
        await _supabase
            .from('timeline_events')
            .insert({
              'relationship_id': relationshipId,
              'logged_by': loggedBy,
              'event_type': eventType,
              'title': title,
              'note': note,
              'mood_score': moodScore,
              'occurred_at': occurredAt.toIso8601String().split('T')[0],
              'visibility': visibility,
            })
            .select()
            .single();

    final event = TimelineEventModel.fromJson(response);

    return event;
  }

  /// Update an existing timeline event
  Future<TimelineEventModel> updateEvent({
    required String eventId,
    String? eventType,
    String? title,
    String? note,
    bool clearNote = false,
    int? moodScore,
    DateTime? occurredAt,
    String? visibility,
  }) async {
    final Map<String, dynamic> updates = {};
    if (visibility != null) updates['visibility'] = visibility;
    if (eventType != null) updates['event_type'] = eventType;
    if (title != null) updates['title'] = title;
    // A null note means "unchanged" unless the user emptied it.
    if (note != null || clearNote) updates['note'] = note;
    if (moodScore != null) updates['mood_score'] = moodScore;
    if (occurredAt != null)
      updates['occurred_at'] = occurredAt.toIso8601String().split('T')[0];

    final response =
        await _supabase
            .from('timeline_events')
            .update(updates)
            .eq('id', eventId)
            .select()
            .single();

    return TimelineEventModel.fromJson(response);
  }

  /// Soft delete (logger only), through the RPC so it does not depend on
  /// PostgREST's return mode (the read policy hides deleted rows).
  Future<void> deleteEvent(String eventId) async {
    await _supabase.rpc(
      'soft_delete_timeline_event',
      params: {'p_event_id': eventId},
    );
  }

  /// Get timeline events for a relationship within a date range
  Future<List<TimelineEventModel>> getEvents({
    required String relationshipId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _supabase
        .from('timeline_events')
        .select('*')
        .eq('relationship_id', relationshipId)
        .isFilter('deleted_at', null)
        .gte('occurred_at', startDate.toIso8601String().split('T')[0])
        .lte('occurred_at', endDate.toIso8601String().split('T')[0])
        .order('occurred_at', ascending: false);

    return response.map((json) => TimelineEventModel.fromJson(json)).toList();
  }

  /// Get events for a specific month (for calendar display)
  Future<List<TimelineEventModel>> getEventsForMonth({
    required String relationshipId,
    required DateTime month,
  }) async {
    final startDate = DateTime(month.year, month.month, 1);
    final endDate = DateTime(month.year, month.month + 1, 0);

    return getEvents(
      relationshipId: relationshipId,
      startDate: startDate,
      endDate: endDate,
    );
  }
}
