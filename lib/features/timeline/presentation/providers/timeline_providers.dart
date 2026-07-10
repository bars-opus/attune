// lib/features/timeline/presentation/providers/timeline_providers.dart
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/data/repositories/timeline_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final timelineRepositoryProvider = Provider<TimelineRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return TimelineRepository(supabase);
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

// Timeline events for current month
final timelineEventsProvider = FutureProvider.family<
  List<TimelineEventModel>,
  DateTime
>((ref, month) async {
  final repository = ref.read(timelineRepositoryProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return [];

  return await repository.getEventsForMonth(
    relationshipId: relationshipId,
    month: month,
  );
});

// Create timeline event
final createTimelineEventProvider = FutureProvider.family<
  TimelineEventModel,
  ({
    String eventType,
    String title,
    DateTime occurredAt,
    String? note,
    int? moodScore,
  })
>((ref, params) async {
  final repository = ref.read(timelineRepositoryProvider);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  final userId = ref.read(currentUserIdProvider);

  if (relationshipId == null) throw Exception('No active relationship found');
  if (userId == null) throw Exception('Not authenticated');

  final event = await repository.createEvent(
    relationshipId: relationshipId,
    loggedBy: userId,
    eventType: params.eventType,
    title: params.title,
    occurredAt: params.occurredAt,
    note: params.note,
    moodScore: params.moodScore,
  );

  // Invalidate the cache for the affected month
  final month = DateTime(params.occurredAt.year, params.occurredAt.month, 1);
  ref.invalidate(timelineEventsProvider(month));

  return event;
});

// Update timeline event
final updateTimelineEventProvider = FutureProvider.family<
  TimelineEventModel,
  ({
    String eventId,
    String? eventType,
    String? title,
    String? note,
    int? moodScore,
    DateTime? occurredAt,
  })
>((ref, params) async {
  final repository = ref.read(timelineRepositoryProvider);

  final event = await repository.updateEvent(
    eventId: params.eventId,
    eventType: params.eventType,
    title: params.title,
    note: params.note,
    moodScore: params.moodScore,
    occurredAt: params.occurredAt,
  );

  // Invalidate caches for affected months
  if (params.occurredAt != null) {
    final month = DateTime(
      params.occurredAt!.year,
      params.occurredAt!.month,
      1,
    );
    ref.invalidate(timelineEventsProvider(month));
  }

  return event;
});

// Delete timeline event
final deleteTimelineEventProvider = FutureProvider.family<void, String>((
  ref,
  eventId,
) async {
  final repository = ref.read(timelineRepositoryProvider);
  await repository.deleteEvent(eventId);

  // Invalidate all timeline caches (simplest approach)
  ref.invalidate(timelineEventsProvider);
});

// Real-time subscription for timeline events
final timelineRealtimeProvider =
    StreamProvider.family<List<TimelineEventModel>, String>((
      ref,
      relationshipId,
    ) {
      final repository = ref.read(timelineRepositoryProvider);
      return repository.subscribeToEvents(relationshipId);
    });
