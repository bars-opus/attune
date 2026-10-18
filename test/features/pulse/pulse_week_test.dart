// test/features/pulse/pulse_week_test.dart
import 'package:attune/features/pulse/domain/pulse_week.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Sunday is its own week ending (matches the server)', () {
    expect(pulseWeekEndingKey(DateTime.utc(2026, 8, 16, 10)), '2026-08-16');
    expect(
      pulseWeekEndingKey(DateTime.utc(2026, 8, 16, 23, 59, 59)),
      '2026-08-16',
    );
  });

  test('a Wednesday rolls forward to the coming Sunday', () {
    expect(pulseWeekEndingKey(DateTime.utc(2026, 8, 12, 10)), '2026-08-16');
    expect(
      pulseWeekEnding(DateTime.utc(2026, 8, 12, 10)).weekday,
      DateTime.sunday,
    );
  });

  test(
    'Saturday 23:59 UTC and Sunday 00:01 UTC share a week; Monday 00:01 UTC does not',
    () {
      expect(
        pulseWeekEndingKey(DateTime.utc(2026, 8, 15, 23, 59)),
        '2026-08-16',
      );
      expect(pulseWeekEndingKey(DateTime.utc(2026, 8, 16, 0, 1)), '2026-08-16');
      expect(pulseWeekEndingKey(DateTime.utc(2026, 8, 17, 0, 1)), '2026-08-23');
    },
  );

  test('local times are converted to UTC first', () {
    // The same instant, expressed with a non-UTC offset, lands on the same key.
    final local = DateTime.utc(2026, 8, 17, 0, 1).toLocal();
    expect(pulseWeekEndingKey(local), '2026-08-23');
  });
}
