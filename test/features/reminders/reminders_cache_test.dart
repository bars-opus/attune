import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/reminders/data/cache/reminders_cache.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userA = 'user-aaa';
const _userB = 'user-bbb';

ReminderModel _reminder(String id, {String title = 'Anniversary dinner'}) {
  return ReminderModel(
    id: id,
    relationshipId: 'rel-1',
    createdBy: _userA,
    reminderType: 'anniversary',
    title: title,
    note: 'Book the usual place',
    remindAt: DateTime.utc(2026, 9, 12),
    recurrence: 'yearly',
    sent: false,
    familyMemberId: null,
    linkedTimelineEventId: 'evt-1',
    createdAt: DateTime.utc(2026, 8, 1, 9),
    updatedAt: DateTime.utc(2026, 8, 1, 9),
  );
}

Future<RemindersCache> _makeCache() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container.read(remindersCacheProvider);
}

void main() {
  group('RemindersCache', () {
    test('round-trips every field a reminder carries', () async {
      final cache = await _makeCache();
      final original = _reminder('r1');

      await cache.writeReminders(_userA, [original]);
      final restored = cache.readReminders(_userA).single;

      expect(restored.id, original.id);
      expect(restored.relationshipId, original.relationshipId);
      expect(restored.createdBy, original.createdBy);
      expect(restored.reminderType, original.reminderType);
      expect(restored.title, original.title);
      expect(restored.note, original.note);
      expect(restored.remindAt, original.remindAt);
      expect(restored.recurrence, original.recurrence);
      expect(restored.sent, original.sent);
      expect(restored.linkedTimelineEventId, original.linkedTimelineEventId);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('handles null note/familyMemberId/linkedTimelineEventId', () async {
      final cache = await _makeCache();
      final bare = ReminderModel(
        id: 'r2',
        relationshipId: 'rel-1',
        createdBy: _userA,
        reminderType: 'checkin',
        title: 'Weekly checkin',
        note: null,
        remindAt: DateTime.utc(2026, 8, 20),
        recurrence: 'weekly',
        sent: false,
        familyMemberId: null,
        linkedTimelineEventId: null,
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
      );

      await cache.writeReminders(_userA, [bare]);
      final restored = cache.readReminders(_userA).single;

      expect(restored.note, isNull);
      expect(restored.familyMemberId, isNull);
      expect(restored.linkedTimelineEventId, isNull);
    });

    test('returns empty on a cold miss', () async {
      final cache = await _makeCache();
      expect(cache.readReminders(_userA), isEmpty);
    });

    test('isolates users', () async {
      final cache = await _makeCache();
      await cache.writeReminders(_userA, [_reminder('a')]);

      expect(cache.readReminders(_userB), isEmpty);
      expect(cache.readReminders(_userA), isNotEmpty);
    });

    test('treats a corrupt payload as a miss', () async {
      SharedPreferences.setMockInitialValues({
        'reminders_cache_${_userA}_reminders': 'not valid json{{',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final cache = container.read(remindersCacheProvider);

      expect(cache.readReminders(_userA), isEmpty);
    });

    test('overwrites rather than appending on repeat writes', () async {
      final cache = await _makeCache();

      await cache.writeReminders(_userA, [_reminder('first')]);
      await cache.writeReminders(_userA, [_reminder('second')]);

      final restored = cache.readReminders(_userA);
      expect(restored, hasLength(1));
      expect(restored.single.id, 'second');
    });
  });
}
