import 'package:attune/features/location/domain/partner_distance.dart';

/// The line the conversation screen shows, and the quieter line under it.
class DistanceCopy {
  const DistanceCopy({required this.headline, this.detail});

  final String headline;
  final String? detail;
}

String _km(double km) {
  if (km >= 1000) {
    final thousands = (km / 1000).toStringAsFixed(km >= 10000 ? 0 : 1);
    return '${thousands}k km';
  }
  return '${km.round()} km';
}

String _duration(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final hours = d.inHours;
  return hours == 1 ? '1 hour' : '$hours hours';
}

String _clock(DateTime local) {
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute${local.hour < 12 ? 'am' : 'pm'}';
}

/// Turns a distance into something worth reading.
///
/// Every branch here is a decision about what a couple should feel, not a
/// formatting choice. The long-distance branches deliberately lead with
/// something OTHER than the number, because the number is the part that
/// does not change.
DistanceCopy distanceCopy(PartnerDistance d, {String? partnerName}) {
  final name = partnerName ?? 'They';

  switch (d.tone) {
    case DistanceTone.together:
      // A number here would be absurd -- and GPS drift alone spans it.
      return const DistanceCopy(headline: 'Practically together');

    case DistanceTone.nearby:
      final mode = travelModeFor(d.km);
      final time = travelTimeFor(d.km, mode);
      return DistanceCopy(
        headline:
            '${_duration(time)} away'
            '${mode == TravelMode.walk ? ' on foot' : ''}',
        detail: d.partnerCity,
      );

    case DistanceTone.sameCountry:
      final time = travelTimeFor(d.km, TravelMode.drive);
      return DistanceCopy(
        headline: '${_duration(time)} by road',
        detail: d.partnerCity == null ? null : '$name in ${d.partnerCity}',
      );

    case DistanceTone.countdown:
      // The strongest thing this feature can say to a long-distance
      // couple: the distance is temporary, and here is when it ends.
      final days = d.daysUntilTogether!;
      return DistanceCopy(
        headline: switch (days) {
          <= 0 => 'Together today',
          1 => 'Together tomorrow',
          _ => '$days days until you\'re together',
        },
        detail: '${_km(d.km)} apart for now',
      );

    case DistanceTone.closing:
      // Someone is travelling. This is the one moment the distance is
      // genuinely news, so it leads.
      final closed = d.kmClosedSinceYesterday!;
      return DistanceCopy(
        headline:
            closed > 0
                ? '${_km(closed)} closer than yesterday'
                : '${_km(closed.abs())} further than yesterday',
        detail: '${_km(d.km)} apart',
      );

    case DistanceTone.distant:
      // The hardest case: far apart, nothing booked. Leading with the
      // distance would just restate the ache, so it leads with the one
      // thing that changes and is useful -- whether they are awake.
      final local = d.partnerLocalTime;
      if (local != null) {
        return DistanceCopy(
          headline: '${_clock(local)} where they are',
          detail: '${_km(d.km)} apart',
        );
      }
      return DistanceCopy(
        headline: '${_km(d.km)} apart',
        detail: d.partnerCity,
      );
  }
}
