import 'package:attune/features/location/domain/partner_distance.dart';

/// Whether a calendar event reads as "we will be together".
///
/// The countdown is the strongest thing this feature can say to a
/// long-distance couple -- it turns a standing distance into something
/// ending -- so getting it WRONG is proportionally bad. "12 days until
/// you're together" above an event that is actually a dentist appointment
/// is worse than showing no countdown at all.
///
/// Inferred from the title rather than requiring a tag: asking a couple
/// to label an event as a reunion is a step nobody would take, and an
/// untagged trip would silently lose the best part of the feature. Kept
/// deliberately narrow instead -- only words that plainly mean travelling
/// to each other. Anything ambiguous shows no countdown.
const _reunionWords = <String>[
  'visit',
  'visiting',
  'flight',
  'flying',
  'trip',
  'arrive',
  'arrives',
  'arriving',
  'landing',
  'lands',
  'together',
  'reunion',
  'seeing you',
  'see you',
  'coming home',
  'comes home',
  'home for',
];

/// Words that look like travel but are not a reunion.
///
/// A work trip is still time apart; counting down to it would invert the
/// meaning entirely.
const _notReunionWords = <String>[
  'work trip',
  'business trip',
  'conference',
  'leaving',
  'leaves',
  'departure',
  'departs',
  'away',
];

bool isReunionEvent(String title) {
  final lower = title.toLowerCase();

  // Checked first: "work trip" contains "trip", and the exclusion has to
  // win or every business trip becomes a countdown to togetherness.
  for (final word in _notReunionWords) {
    if (lower.contains(word)) return false;
  }

  for (final word in _reunionWords) {
    if (lower.contains(word)) return true;
  }

  return false;
}

/// Days until [event], counted in whole local days.
///
/// Counted by DATE, not by elapsed hours: an event at 9am tomorrow is
/// "tomorrow" whether you check at midnight or at 8am. Hour-based
/// arithmetic would call it "today" for part of the night, which is both
/// wrong and briefly cruel.
int daysUntil(DateTime event, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final startOfEvent = DateTime(event.year, event.month, event.day);
  return startOfEvent.difference(startOfToday).inDays;
}

/// Adds a countdown when the calendar holds a reunion, only for couples
/// far enough apart for a countdown to mean something.
PartnerDistance withReunion(
  PartnerDistance d,
  Iterable<(String, DateTime)> events, {
  DateTime? now,
}) {
  if (d.km < PartnerDistance.sameCountryKm) return d;
  int? soonest;
  for (final (title, at) in events) {
    if (!isReunionEvent(title)) continue;
    final days = daysUntil(at, now: now);
    if (days < 0) continue;
    if (soonest == null || days < soonest) soonest = days;
  }
  if (soonest == null) return d;
  return PartnerDistance(
    km: d.km,
    partnerCity: d.partnerCity,
    partnerUtcOffsetMinutes: d.partnerUtcOffsetMinutes,
    daysUntilTogether: soonest,
    together: d.together,
  );
}
