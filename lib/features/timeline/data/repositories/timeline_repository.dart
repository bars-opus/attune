// lib/features/timeline/data/repositories/timeline_repository.dart

import 'dart:async';

import 'package:attune/core/notifications/services/attune_notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/timeline_event_model.dart';

class TimelineRepository {
  final SupabaseClient _supabase;
  final AttuneNotificationService _notificationService;

  TimelineRepository(this._supabase)
    : _notificationService = AttuneNotificationService();

  /// Create a new timeline event
  Future<TimelineEventModel> createEvent({
    required String relationshipId,
    required String loggedBy,
    required String eventType,
    required String title,
    required DateTime occurredAt,
    String? note,
    int? moodScore,
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
            })
            .select()
            .single();

    final event = TimelineEventModel.fromJson(response);

    // Send notification to partner (skip for conflicts - per spec Section 10)
    if (eventType != 'conflict') {
      await _notifyPartner(
        relationshipId: relationshipId,
        loggedBy: loggedBy,
        eventType: eventType,
        title: title,
      );
    }

    return event;
  }

  /// Update an existing timeline event
  Future<TimelineEventModel> updateEvent({
    required String eventId,
    String? eventType,
    String? title,
    String? note,
    int? moodScore,
    DateTime? occurredAt,
  }) async {
    final Map<String, dynamic> updates = {};
    if (eventType != null) updates['event_type'] = eventType;
    if (title != null) updates['title'] = title;
    if (note != null) updates['note'] = note;
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

  /// Soft delete a timeline event
  Future<void> deleteEvent(String eventId) async {
    await _supabase
        .from('timeline_events')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', eventId);
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

  /// Send notification to partner when a moment is logged
  Future<void> _notifyPartner({
    required String relationshipId,
    required String loggedBy,
    required String eventType,
    required String title,
  }) async {
    try {
      // Get relationship members
      final relationshipRes =
          await _supabase
              .from('relationships')
              .select('user_a, user_b')
              .eq('id', relationshipId)
              .single();

      final partnerId =
          loggedBy == relationshipRes['user_a']
              ? relationshipRes['user_b']
              : relationshipRes['user_a'];

      if (partnerId == null) return;

      // Get logged by user's name
      final profileRes =
          await _supabase
              .from('profiles')
              .select('display_name')
              .eq('id', loggedBy)
              .single();

      final partnerName =
          profileRes['display_name'] as String? ?? 'Your partner';

      await _notificationService.notifyPartnerMomentLogged(
        partnerId: partnerId,
        partnerName: partnerName,
        eventType: eventType,
        title: title,
      );
    } catch (e) {
      print('Error sending partner notification: $e');
    }
  }

  /// Subscribe to real-time updates for timeline events
  Stream<List<TimelineEventModel>> subscribeToEvents(String relationshipId) {
    // The repository currently serves pull-based reads only. Realtime can be
    // reintroduced once the timeline event stream is wired to the current
    // Supabase channel API.
    return Stream<List<TimelineEventModel>>.value(const []);
  }
}
