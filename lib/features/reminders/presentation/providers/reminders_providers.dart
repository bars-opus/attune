// lib/features/reminders/presentation/providers/reminders_providers.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/data/repositories/timeline_repository.dart';
import '../../data/cache/reminders_cache.dart';
import '../../data/models/family_member_model.dart';
import '../../data/models/reminder_model.dart';
import '../../data/repositories/reminders_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final remindersRepositoryProvider = Provider<RemindersRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return RemindersRepository(supabase);
});

// Feature-local copy of the current active relationship id, following the
// same per-feature convention already used by Timeline/Pulse/Verdict/
// ConflictTranslator in this codebase (each feature keeps its own copy
// rather than importing across feature boundaries).
final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final response = await supabase
      .from('relationships')
      .select('id')
      .or('user_a.eq.$userId,user_b.eq.$userId')
      .eq('status', 'active')
      .maybeSingle();
  return response?['id'] as String?;
});

final remindersListProvider =
    AsyncNotifierProvider<RemindersListNotifier, List<ReminderModel>>(
      RemindersListNotifier.new,
    );

/// Cache-then-refresh: paints the last-known reminders immediately on a
/// cold start so ConversationsScreen's calendar row isn't showing "No
/// upcoming events" while the fetch runs, then swaps in fresh data when it
/// lands. Mirrors forums' _CachedTopicsNotifier (forum_providers.dart).
///
/// _servedCache is static so it survives this notifier being recreated by
/// invalidate() — after creating/deleting a reminder, serving cache first
/// would briefly re-show the pre-change list.
class RemindersListNotifier extends AsyncNotifier<List<ReminderModel>> {
  static bool _servedCache = false;

  @override
  Future<List<ReminderModel>> build() async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final cache = ref.read(remindersCacheProvider);

    if (!_servedCache && userId != null) {
      _servedCache = true;
      final cached = cache.readReminders(userId);
      if (cached.isNotEmpty) {
        _refreshInBackground(cache, userId);
        return cached;
      }
    }

    final reminders = await _fetch();
    if (userId != null) {
      unawaited(cache.writeReminders(userId, reminders));
    }
    return reminders;
  }

  Future<List<ReminderModel>> _fetch() async {
    final relationshipId = await ref.read(currentRelationshipIdProvider.future);
    if (relationshipId == null) return const [];
    return ref.read(remindersRepositoryProvider).listReminders(relationshipId);
  }

  /// Fetches behind an already-painted cached list. Never surfaces an
  /// AsyncLoading (that would flash the cache away) and swallows failure —
  /// the user keeps reading the cached list until a later refresh succeeds.
  Future<void> _refreshInBackground(RemindersCache cache, String userId) async {
    try {
      final reminders = await _fetch();
      state = AsyncData(reminders);
      unawaited(cache.writeReminders(userId, reminders));
    } catch (error) {
      debugPrint('[reminders] background refresh failed: ${error.runtimeType}');
    }
  }
}

final familyMembersListProvider = FutureProvider<List<FamilyMemberModel>>((ref) async {
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return const [];
  return ref.read(remindersRepositoryProvider).listFamilyMembers(relationshipId);
});

final createReminderProvider = FutureProvider.family<
  ReminderModel,
  ({
    String reminderType,
    String title,
    String? note,
    DateTime remindAt,
    String recurrence,
    String? familyMemberId,
  })
>((ref, params) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser!.id;
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) {
    throw StateError('No active relationship');
  }
  final reminder = await ref.read(remindersRepositoryProvider).createReminder(
        relationshipId: relationshipId,
        createdBy: userId,
        reminderType: params.reminderType,
        title: params.title,
        note: params.note,
        remindAt: params.remindAt,
        recurrence: params.recurrence,
        familyMemberId: params.familyMemberId,
      );
  ref.invalidate(remindersListProvider);
  return reminder;
});

final deleteReminderProvider = FutureProvider.family<void, String>((ref, id) async {
  await ref.read(remindersRepositoryProvider).deleteReminder(id);
  ref.invalidate(remindersListProvider);
});

final upsertFamilyMemberProvider = FutureProvider.family<
  String,
  ({String? id, String name, DateTime? birthday})
>((ref, params) async {
  final memberId = await ref.read(remindersRepositoryProvider).upsertFamilyMember(
        id: params.id,
        name: params.name,
        birthday: params.birthday,
      );
  ref.invalidate(familyMembersListProvider);
  ref.invalidate(remindersListProvider);
  return memberId;
});

final deleteFamilyMemberProvider = FutureProvider.family<void, String>((ref, id) async {
  await ref.read(remindersRepositoryProvider).deleteFamilyMember(id);
  ref.invalidate(familyMembersListProvider);
  ref.invalidate(remindersListProvider);
});

final timelineAnniversariesThisMonthProvider =
    FutureProvider<List<TimelineEventModel>>((ref) async {
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return const [];
  final supabase = ref.read(supabaseClientProvider);
  final events = await TimelineRepository(supabase).getEventsForMonth(
    relationshipId: relationshipId,
    month: DateTime.now(),
  );
  return events.where((e) => e.eventType == 'anniversary').toList(growable: false);
});
