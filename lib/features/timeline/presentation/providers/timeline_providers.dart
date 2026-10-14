// lib/features/timeline/presentation/providers/timeline_providers.dart
import 'dart:async';

import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    as reminders_providers;
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/data/repositories/timeline_repository.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
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

/// The cache key for a month of moments: its first day at midnight.
/// Every reader and every invalidation must go through this, or a key
/// carrying a time of day silently misses the refresh.
DateTime timelineMonthKey(DateTime date) => DateTime(date.year, date.month);

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
    String? visibility,
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
    visibility: params.visibility ?? 'shared',
  );

  // Invalidate the cache for the affected month
  ref.invalidate(timelineEventsProvider(timelineMonthKey(params.occurredAt)));

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
    String? visibility,
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
    visibility: params.visibility,
  );

  // Invalidate caches for affected months
  if (params.occurredAt != null) {
    ref.invalidate(
      timelineEventsProvider(timelineMonthKey(params.occurredAt!)),
    );
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

final _togetherSignalChannels = <String, RealtimeChannel>{};

/// Emits when anything Together shows changes for [relationshipId]
/// (moments, reminders, family birthdays), once on every (re)subscribe,
/// and on app resume. Realtime is only a refetch signal here, exactly
/// as planningChangeSignalProvider.
final togetherChangeSignalProvider = StreamProvider.autoDispose
    .family<void, String>((ref, relationshipId) {
      final supabase = ref.read(supabaseClientProvider);
      final controller = StreamController<void>.broadcast();
      void emit() {
        if (!controller.isClosed) controller.add(null);
      }

      final channel = supabase
          .channel('together-signals:$relationshipId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'together_change_signals',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'relationship_id',
              value: relationshipId,
            ),
            callback: (_) => emit(),
          )
          .subscribe((status, _) {
            if (status == RealtimeSubscribeStatus.subscribed) emit();
          });
      _togetherSignalChannels[relationshipId] = channel;
      final lifecycle = AppLifecycleListener(onResume: emit);

      ref.onDispose(() {
        lifecycle.dispose();
        final c = _togetherSignalChannels.remove(relationshipId);
        if (c != null) unawaited(supabase.removeChannel(c));
        controller.close();
      });
      return controller.stream;
    });

/// Watch this while the Timeline is on screen: every Together signal
/// refetches moments (all months) and reminders.
final timelineAutoRefreshProvider = Provider.autoDispose.family<void, String>((
  ref,
  relationshipId,
) {
  ref.listen<AsyncValue<void>>(togetherChangeSignalProvider(relationshipId), (
    _,
    __,
  ) {
    ref.invalidate(timelineEventsProvider);
    ref.invalidate(reminders_providers.remindersListProvider);
  });
});
