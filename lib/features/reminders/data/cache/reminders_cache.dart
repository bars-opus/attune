// lib/features/reminders/data/cache/reminders_cache.dart

import 'package:attune/core/cache/feed_cache_store.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final remindersCacheProvider = Provider<RemindersCache>((ref) {
  return RemindersCache(ref.watch(sharedPreferencesProvider));
});

/// Last-known reminders, so ConversationsScreen's calendar row paints
/// instantly on relaunch instead of showing "No upcoming events" while the
/// fetch runs.
///
/// Envelope handling (version, TTL, clock skew, corruption, size cap) lives
/// in [FeedCacheStore]; this only supplies the encode/decode and a single
/// fixed feed key.
class RemindersCache extends FeedCacheStore<ReminderModel> {
  RemindersCache(super.prefs);

  static const String _feedKey = 'reminders';

  @override
  String get keyPrefix => 'reminders_cache_';

  @override
  int get schemaVersion => 1;

  @override
  Map<String, dynamic> encode(ReminderModel item) => item.toJson();

  @override
  ReminderModel decode(Map<String, dynamic> json) =>
      ReminderModel.fromJson(json);

  List<ReminderModel> readReminders(String userId) => read(_feedKey, userId);

  Future<void> writeReminders(String userId, List<ReminderModel> reminders) =>
      write(_feedKey, userId, reminders);

  Future<void> clearReminders(String userId) => clear(_feedKey, userId);
}
