import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReminderModel.fromJson parses a one-off reminder', () {
    final reminder = ReminderModel.fromJson({
      'id': 'rem-1',
      'relationship_id': 'rel-1',
      'created_by': 'user-1',
      'reminder_type': 'anniversary',
      'title': 'Our Anniversary',
      'note': null,
      'remind_at': '2026-09-14T00:00:00Z',
      'recurrence': 'none',
      'sent': false,
      'family_member_id': null,
      'linked_timeline_event_id': null,
      'created_at': '2026-08-02T10:00:00Z',
      'updated_at': '2026-08-02T10:00:00Z',
    });

    expect(reminder.id, 'rem-1');
    expect(reminder.isRecurring, isFalse);
    expect(reminder.isAnniversary, isTrue);
    expect(reminder.isBirthday, isFalse);
  });

  test('ReminderModel.fromJson parses a recurring birthday reminder', () {
    final reminder = ReminderModel.fromJson({
      'id': 'rem-2',
      'relationship_id': 'rel-1',
      'created_by': 'user-1',
      'reminder_type': 'birthday',
      'title': 'Emma\'s birthday',
      'note': 'Loves dinosaurs',
      'remind_at': '2026-03-10T00:00:00Z',
      'recurrence': 'yearly',
      'sent': false,
      'family_member_id': 'fam-1',
      'linked_timeline_event_id': null,
      'created_at': '2026-08-02T10:00:00Z',
      'updated_at': '2026-08-02T10:00:00Z',
    });

    expect(reminder.isRecurring, isTrue);
    expect(reminder.isBirthday, isTrue);
    expect(reminder.familyMemberId, 'fam-1');
    expect(reminder.note, 'Loves dinosaurs');
  });

  Map<String, dynamic> json(String remindAt) => {
    'id': 'rem-9',
    'relationship_id': 'rel-1',
    'created_by': 'user-1',
    'reminder_type': 'birthday',
    'title': 'Ama',
    'note': null,
    'remind_at': remindAt,
    'recurrence': 'yearly',
    'sent': false,
    'family_member_id': null,
    'linked_timeline_event_id': null,
    'created_at': '2026-08-02T10:00:00Z',
    'updated_at': '2026-08-02T10:00:00Z',
  };

  test(
    'remindAt is the picked calendar date, whatever offset the server sent',
    () {
      expect(
        ReminderModel.fromJson(json('2026-10-20T00:00:00+00:00')).remindAt,
        DateTime(2026, 10, 20),
      );
      expect(
        ReminderModel.fromJson(json('2026-10-20')).remindAt,
        DateTime(2026, 10, 20),
      );
    },
  );

  test('toJson writes a plain date, and the cache round-trips it', () {
    final r = ReminderModel.fromJson(json('2026-02-28T00:00:00Z'));
    expect(r.toJson()['remind_at'], '2026-02-28');
    expect(ReminderModel.fromJson(r.toJson()).remindAt, DateTime(2026, 2, 28));
  });

  test('reminderDateString pads month and day', () {
    expect(reminderDateString(DateTime(2027, 3, 4, 23, 59)), '2027-03-04');
  });

  test('when to hear: read from the row, and the old default for older rows', () {
    Map<String, dynamic> row([List<int>? days]) => {
      'id': 'rem-9', 'relationship_id': 'rel-1', 'created_by': 'user-1',
      'reminder_type': 'birthday', 'title': 'Mum', 'note': null,
      'remind_at': '2026-03-10T00:00:00Z', 'recurrence': 'yearly', 'sent': false,
      'family_member_id': null, 'linked_timeline_event_id': null,
      'created_at': '2026-08-02T10:00:00Z', 'updated_at': '2026-08-02T10:00:00Z',
      if (days != null) 'remind_days_before': days,
    };
    expect(ReminderModel.fromJson(row([1, 7])).remindDaysBefore, [1, 7]);
    expect(ReminderModel.fromJson(row()).remindDaysBefore, [0, 3]);
    expect(ReminderModel.fromJson(ReminderModel.fromJson(row([7])).toJson()).remindDaysBefore, [7]);
  });
}
