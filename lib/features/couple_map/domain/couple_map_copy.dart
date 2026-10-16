import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
// widgets.dart (not foundation.dart): it also exports `characters`.
import 'package:flutter/widgets.dart';

/// The top-left chip: always visible, so you always know who can see you.
String sharingChipLabel(
  PresenceState s, {
  required LocationAccess access,
  required String partnerName,
  required DateTime now,
}) {
  switch (s.status) {
    case PresenceStatus.off:
      return 'Off';
    case PresenceStatus.paused:
      final until = s.pausedUntil;
      if (until == null) return 'Paused';
      final left = until.difference(now);
      return left.isNegative || left == Duration.zero
          ? 'Paused'
          : 'Paused · ${pauseRemainingLabel(left)}';
    case PresenceStatus.sharing:
      if (access != LocationAccess.granted) return 'Location is off for Attune';
      return 'Sharing my area with $partnerName';
  }
}

/// "42 min", "1 h", "7 h 5 min". Rounded up, so it never says 0.
String pauseRemainingLabel(Duration d) {
  final mins = (d.inSeconds / 60).ceil().clamp(1, 1 << 30);
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

enum CoupleMapNotice { notSharing, locationOff, justYou }

/// The one line shown instead of the distance card, or null when the card
/// shows. Every partner-side reason (paused, stopped, stale, never shared)
/// and my own pause give the same answer: the server can't tell them apart
/// and neither may the copy (spec §3.4).
CoupleMapNotice? coupleMapNotice(CoupleMapPresence p, LocationAccess access) {
  if (p.state.status == PresenceStatus.off) return CoupleMapNotice.notSharing;
  if (p.partnerDistance != null) return null;
  if (p.state.status == PresenceStatus.sharing &&
      access != LocationAccess.granted) {
    return CoupleMapNotice.locationOff;
  }
  return CoupleMapNotice.justYou;
}

String noticeText(CoupleMapNotice n) => switch (n) {
  CoupleMapNotice.notSharing =>
    'See how far apart you are — shares your neighbourhood, never your address',
  CoupleMapNotice.locationOff =>
    'Turn on location for Attune to share your area',
  CoupleMapNotice.justYou => 'Just you on the map right now',
};

@immutable
class DistanceCardCopy {
  const DistanceCardCopy({
    required this.headline,
    required this.details,
    required this.together,
  });
  final String headline;

  /// Segments joined with " · "; empty when there is nothing to add.
  final String details;
  final bool together;
}

DistanceCardCopy distanceCardCopy(
  PartnerDistance d, {
  String? partnerName,
  int? myUtcOffsetMinutes,
  required DateTime now,
}) {
  if (d.tone == DistanceTone.together) {
    return DistanceCardCopy(
      headline:
          d.partnerCity == null ? 'Together' : 'Together · ${d.partnerCity}',
      details: '',
      together: true,
    );
  }
  final copy = distanceCopy(d, partnerName: partnerName, now: now);
  final offset = d.partnerUtcOffsetMinutes;
  final segments = <String>[
    if (!copy.headline.contains(' km')) '${formatKm(d.km)} apart',
    if (d.partnerCity != null) 'in ${d.partnerCity}',
    if (offset != null &&
        offset != myUtcOffsetMinutes &&
        !copy.headline.endsWith('where they are'))
      '${formatClock(now.toUtc().add(Duration(minutes: offset)))} there',
  ];
  return DistanceCardCopy(
    headline: copy.headline,
    details: segments.join(' · '),
    together: false,
  );
}

/// Up to two initials for an avatar with no photo.
String initialsOf(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}
