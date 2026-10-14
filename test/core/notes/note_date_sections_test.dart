import 'package:attune/core/notes/note_date_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 20, 15);

  test('groups any item by the date it is given, newest group first', () {
    final items = [
      (name: 'today', at: DateTime(2026, 11, 20, 8)),
      (name: 'old', at: DateTime(2025, 3, 1)),
      (name: 'yesterday', at: DateTime(2026, 11, 19, 22)),
      (name: 'week', at: DateTime(2026, 11, 15)),
      (name: 'month', at: DateTime(2026, 11, 1)),
      (name: 'june', at: DateTime(2026, 6, 4)),
    ];
    final s = noteDateSections(items, (i) => i.at, now);
    expect(s.map((g) => g.title), ['Today', 'Yesterday', 'Previous 7 Days', 'Previous 30 Days', 'June', '2025']);
    expect(s.first.items.single.name, 'today');
  });

  test('row dates: time today, Yesterday, weekday this week, else the date', () {
    expect(noteRowDate(DateTime(2026, 11, 20, 9, 5), now), contains('9:05'));
    expect(noteRowDate(DateTime(2026, 11, 19, 9), now), 'Yesterday');
    expect(noteRowDate(DateTime(2026, 11, 16, 9), now), 'Monday');
    expect(noteRowDate(DateTime(2026, 10, 2, 9), now), '10/2/2026');
  });
}
