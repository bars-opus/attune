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
}
