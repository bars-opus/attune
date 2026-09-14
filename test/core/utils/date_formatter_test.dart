import 'package:attune/core/utils/date_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MyDateFormat.toWeekdayMonth', () {
    test('abbreviates the weekday and spells the full month, no day or '
        'year', () {
      // 2026-11-08 is a Sunday.
      expect(
        MyDateFormat.toWeekdayMonth(DateTime(2026, 11, 8)),
        'Sun, November',
      );
    });

    test('never includes a day number or a year', () {
      final formatted = MyDateFormat.toWeekdayMonth(DateTime(2026, 11, 8));
      expect(formatted, isNot(contains('8')));
      expect(formatted, isNot(contains('2026')));
    });

    test('the full-length toDate keeps day and year — the two formats '
        'diverge by design, this one is the shortened one', () {
      final date = DateTime(2026, 11, 8);
      expect(
        MyDateFormat.toDate(date),
        isNot(equals(MyDateFormat.toWeekdayMonth(date))),
      );
      expect(MyDateFormat.toDate(date), contains('2026'));
    });
  });
}
