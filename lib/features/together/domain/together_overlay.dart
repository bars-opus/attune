/// The busy overlay (Together Phase 6): only *when* someone is busy ever
/// leaves their phone, rounded outward to 30 minutes, 14 days ahead.
library;

enum OverlayLevel {
  off('off'),
  freeWindows('free_windows'),
  strips('strips');

  const OverlayLevel(this.wire);
  final String wire;

  static OverlayLevel fromWire(String? s) =>
      values.firstWhere((v) => v.wire == s, orElse: () => off);
}

DateTime _local(Object v) => DateTime.parse(v as String).toLocal();

/// A time we're both free (computed on the server, plan R1).
class FreeWindow {
  const FreeWindow({
    required this.start,
    required this.end,
    required this.partnerFrom,
    required this.partnerTo,
    required this.partnerDiffers,
  });

  factory FreeWindow.fromRow(Map<String, dynamic> r) => FreeWindow(
    start: _local(r['starts_at']),
    end: _local(r['ends_at']),
    partnerFrom: r['partner_from'] as String? ?? '',
    partnerTo: r['partner_to'] as String? ?? '',
    partnerDiffers: r['partner_differs'] as bool? ?? false,
  );

  final DateTime start;
  final DateTime end;

  /// The window in my partner's own clock ("08:00"), for long distance.
  final String partnerFrom;
  final String partnerTo;
  final bool partnerDiffers;
}

class BusyStrip {
  const BusyStrip({
    required this.isMine,
    required this.start,
    required this.end,
  });

  factory BusyStrip.fromRow(Map<String, dynamic> r) => BusyStrip(
    isMine: r['is_mine'] as bool? ?? false,
    start: _local(r['starts_at']),
    end: _local(r['ends_at']),
  );

  final bool isMine;
  final DateTime start;
  final DateTime end;
}

/// One entry read from the phone's calendar: times and flags only.
class DeviceBusy {
  const DeviceBusy({
    required this.start,
    required this.end,
    this.allDay = false,
    this.free = false,
    this.cancelled = false,
    this.calendarId,
  });

  final DateTime start;
  final DateTime end;
  final bool allDay;
  final bool free;
  final bool cancelled;

  /// Which phone calendar it came from (lets the calendar copy be skipped).
  final String? calendarId;
}

const _slotMs = 30 * 60 * 1000;

DateTime _floor(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
  (t.millisecondsSinceEpoch ~/ _slotMs) * _slotMs,
  isUtc: true,
);

DateTime _ceil(DateTime t) {
  final ms = t.millisecondsSinceEpoch;
  final up = ms % _slotMs == 0 ? ms : (ms ~/ _slotMs + 1) * _slotMs;
  return DateTime.fromMillisecondsSinceEpoch(up, isUtc: true);
}

/// What we upload (plan R4): timed, busy, not cancelled; now..now+14 days;
/// rounded outward to the UTC half-hour; overlaps merged.
List<({DateTime start, DateTime end})> busyBlocksFrom(
  Iterable<DeviceBusy> events,
  DateTime now,
) {
  final from = _floor(now.toUtc());
  final to = now.toUtc().add(const Duration(days: 14));
  final raw = <({DateTime start, DateTime end})>[];
  for (final e in events) {
    if (e.allDay || e.free || e.cancelled) continue;
    final s = e.start.toUtc().isBefore(from) ? from : e.start.toUtc();
    final en = e.end.toUtc().isAfter(to) ? to : e.end.toUtc();
    if (!en.isAfter(s)) continue;
    raw.add((start: _floor(s), end: _ceil(en)));
  }
  raw.sort((a, b) => a.start.compareTo(b.start));
  final merged = <({DateTime start, DateTime end})>[];
  for (final b in raw) {
    if (merged.isNotEmpty && !b.start.isAfter(merged.last.end)) {
      final last = merged.removeLast();
      merged.add((
        start: last.start,
        end: b.end.isAfter(last.end) ? b.end : last.end,
      ));
    } else {
      merged.add(b);
    }
  }
  return merged;
}
