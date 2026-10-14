import 'package:attune/features/together/domain/together_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceBusy _e(
  DateTime s,
  DateTime e, {
  bool allDay = false,
  bool free = false,
  bool cancelled = false,
}) => DeviceBusy(
  start: s,
  end: e,
  allDay: allDay,
  free: free,
  cancelled: cancelled,
);

void main() {
  final now = DateTime.utc(2026, 11, 10, 8, 5);

  test('times round outward to 30 minutes and overlaps merge', () {
    final b = busyBlocksFrom([
      _e(DateTime.utc(2026, 11, 10, 9, 10), DateTime.utc(2026, 11, 10, 9, 40)),
      _e(DateTime.utc(2026, 11, 10, 9, 50), DateTime.utc(2026, 11, 10, 10, 20)),
      _e(DateTime.utc(2026, 11, 10, 14, 0), DateTime.utc(2026, 11, 10, 15, 0)),
    ], now);
    expect(
      b.map((x) => '${x.start.toIso8601String()}/${x.end.toIso8601String()}'),
      [
        '2026-11-10T09:00:00.000Z/2026-11-10T10:30:00.000Z',
        '2026-11-10T14:00:00.000Z/2026-11-10T15:00:00.000Z',
      ],
    );
  });

  test('all-day, free and cancelled entries are not busy', () {
    final b = busyBlocksFrom([
      _e(DateTime.utc(2026, 11, 11), DateTime.utc(2026, 11, 12), allDay: true),
      _e(
        DateTime.utc(2026, 11, 10, 12),
        DateTime.utc(2026, 11, 10, 13),
        free: true,
      ),
      _e(
        DateTime.utc(2026, 11, 10, 16),
        DateTime.utc(2026, 11, 10, 17),
        cancelled: true,
      ),
    ], now);
    expect(b, isEmpty);
  });

  test('only now to 14 days ahead, clipped at both ends', () {
    final b = busyBlocksFrom([
      _e(DateTime.utc(2026, 11, 9, 9), DateTime.utc(2026, 11, 9, 10)), // past
      _e(
        DateTime.utc(2026, 11, 10, 7),
        DateTime.utc(2026, 11, 10, 9),
      ), // started
      _e(
        DateTime.utc(2026, 11, 24, 7),
        DateTime.utc(2026, 11, 24, 23),
      ), // runs past 14 days
      _e(DateTime.utc(2026, 12, 1), DateTime.utc(2026, 12, 1, 1)), // beyond
    ], now);
    expect(b.first.start, DateTime.utc(2026, 11, 10, 8));
    expect(b.last.end, DateTime.utc(2026, 11, 24, 8, 30));
    expect(b.length, 2);
  });

  test('a :45 zone (Nepal) still rounds on the UTC half-hour grid', () {
    final kathmandu = DateTime.utc(2026, 11, 10, 3, 15); // 09:00 local
    final b = busyBlocksFrom([
      _e(kathmandu, kathmandu.add(const Duration(minutes: 30))),
    ], now.subtract(const Duration(hours: 6)));
    expect(
      [b.single.start, b.single.end],
      [DateTime.utc(2026, 11, 10, 3), DateTime.utc(2026, 11, 10, 4)],
    );
  });

  test('rows map; levels read from the wire', () {
    final w = FreeWindow.fromRow({
      'starts_at': '2026-11-10T13:00:00+00:00',
      'ends_at': '2026-11-10T15:00:00+00:00',
      'partner_from': '08:00',
      'partner_to': '10:00',
      'partner_differs': true,
    });
    expect(
      [w.start, w.partnerFrom, w.partnerDiffers],
      [DateTime.utc(2026, 11, 10, 13).toLocal(), '08:00', true],
    );
    expect(OverlayLevel.fromWire('strips'), OverlayLevel.strips);
    expect(OverlayLevel.fromWire(null), OverlayLevel.off);
  });
}
