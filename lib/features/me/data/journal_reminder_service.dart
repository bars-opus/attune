import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// J3's weekly reminder (Spec 1 §3.10, §4.2): a weekday (ISO, Monday 1)
/// and a local time, both kept while it's off.
@immutable
class JournalReminder {
  const JournalReminder({required this.enabled, this.isoWeekday, this.time});

  static const off = JournalReminder(enabled: false);

  final bool enabled;
  final int? isoWeekday;
  final TimeOfDay? time;

  /// get_my_journal_reminder()'s `{enabled, iso_weekday, local_time}`.
  factory JournalReminder.fromJson(Object? json) {
    if (json is! Map) return off;
    final day = json['iso_weekday'];
    final raw = json['local_time'];
    TimeOfDay? time;
    if (raw is String) {
      final parts = raw.split(':');
      final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
      final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (hour != null && minute != null) {
        time = TimeOfDay(hour: hour, minute: minute);
      }
    }
    return JournalReminder(
      enabled: json['enabled'] == true,
      isoWeekday: day is int && day >= 1 && day <= 7 ? day : null,
      time: time,
    );
  }
}

/// The reminder's times: from 08:00 up to (not including) 22:00 local, so
/// quiet hours (22:00-08:00) never move it to another day (W3 plan P-21).
bool reminderTimeAllowed(TimeOfDay time) => time.hour >= 8 && time.hour < 22;

/// `HH:mm`, as set_my_journal_reminder takes a time.
String reminderWireTime(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

enum ReminderRefusal { quietHours, invalid }

class ReminderRefused implements Exception {
  const ReminderRefused(this.reason);
  final ReminderRefusal reason;
}

typedef ReminderRpc =
    Future<Object?> Function(String fn, Map<String, dynamic>? params);

final journalReminderRpcProvider = Provider<ReminderRpc>(
  (ref) => (fn, params) => Supabase.instance.client.rpc(fn, params: params),
);

class JournalReminderService {
  JournalReminderService(this._rpc);

  final ReminderRpc _rpc;

  static const timeout = Duration(seconds: 15);

  Future<JournalReminder> read() async => JournalReminder.fromJson(
    await _rpc('get_my_journal_reminder', null).timeout(timeout),
  );

  Future<void> save(JournalReminder reminder) async {
    try {
      await _rpc('set_my_journal_reminder', {
        'p_enabled': reminder.enabled,
        'p_iso_weekday': reminder.isoWeekday,
        'p_local_time':
            reminder.time == null ? null : reminderWireTime(reminder.time!),
      }).timeout(timeout);
    } on PostgrestException catch (error) {
      if (error.message.startsWith('journal_reminder:quiet_hours')) {
        throw const ReminderRefused(ReminderRefusal.quietHours);
      }
      if (error.message.startsWith('journal_reminder:')) {
        throw const ReminderRefused(ReminderRefusal.invalid);
      }
      rethrow;
    }
  }
}

final journalReminderServiceProvider = Provider<JournalReminderService>(
  (ref) => JournalReminderService(ref.watch(journalReminderRpcProvider)),
);

/// The signed-in person's reminder, read whenever a screen shows it (so a
/// change of account never shows the last one's). Unreadable is unknown,
/// never "Off" (B7 review I-1): an error state, read again [retryAfter]
/// later (a reconnect), on resume and when the sheet opens.
class JournalReminderNotifier
    extends AutoDisposeAsyncNotifier<JournalReminder> {
  static const retryAfter = Duration(seconds: 30);

  @override
  Future<JournalReminder> build() async {
    try {
      return await ref.read(journalReminderServiceProvider).read();
    } catch (error) {
      debugPrint('[journal-reminder] read failed: ${error.runtimeType}');
      final retry = Timer(retryAfter, ref.invalidateSelf);
      ref.onDispose(retry.cancel);
      rethrow;
    }
  }

  /// Saves it; throws ReminderRefused or a transient error to the caller.
  Future<void> save(JournalReminder reminder) async {
    await ref.read(journalReminderServiceProvider).save(reminder);
    state = AsyncData(reminder);
  }
}

/// The reminder only once the server has answered: null while it is being
/// read or couldn't be read (B7 review I-1), so nothing shows "Off" or
/// saves over the real day and time meanwhile.
JournalReminder? knownReminder(AsyncValue<JournalReminder> value) =>
    value.hasValue && !value.hasError && !value.isLoading ? value.value : null;

final journalReminderProvider =
    AsyncNotifierProvider.autoDispose<JournalReminderNotifier, JournalReminder>(
      JournalReminderNotifier.new,
    );
