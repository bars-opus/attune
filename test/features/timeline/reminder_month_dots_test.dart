import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/timeline/presentation/widgets/upcoming_reminders_section.dart';
import 'package:flutter_test/flutter_test.dart';

ReminderModel _r(String id, DateTime at, {String recurrence = 'yearly'}) =>
    ReminderModel(
      id: id,
      relationshipId: 'rel',
      createdBy: 'u',
      reminderType: 'anniversary',
      title: id,
      remindAt: at,
      recurrence: recurrence,
      sent: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('a yearly reminder shows in its month of any year, even far ahead', () {
    final dots = remindersByDateInMonth([
      _r('anniv', DateTime(2024, 10, 20)),
    ], DateTime(2028, 10));
    expect(dots.keys, [DateTime(2028, 10, 20)]);
  });

  test('a past one-off shows only in its own month', () {
    final r = _r('trip', DateTime(2025, 3, 9), recurrence: 'none');
    expect(remindersByDateInMonth([r], DateTime(2025, 3)).keys, [
      DateTime(2025, 3, 9),
    ]);
    expect(remindersByDateInMonth([r], DateTime(2026, 3)), isEmpty);
  });

  test('Feb 29 lands on Feb 28 in a non-leap year', () {
    final dots = remindersByDateInMonth([
      _r('leap', DateTime(2024, 2, 29)),
    ], DateTime(2027, 2));
    expect(dots.keys, [DateTime(2027, 2, 28)]);
  });

  test('other months get nothing', () {
    expect(
      remindersByDateInMonth([
        _r('a', DateTime(2024, 10, 20)),
      ], DateTime(2028, 11)),
      isEmpty,
    );
  });
}
