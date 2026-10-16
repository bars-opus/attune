// lib/features/location/domain/couple_map_presence.dart
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:flutter/foundation.dart';

/// How fresh an area is. The server sends only this, never a time:
/// times would read as "when they last opened the app".
enum PresenceFreshness { fresh, fading }

@immutable
class PresenceArea {
  const PresenceArea({
    this.cellLat,
    this.cellLng,
    this.city,
    this.country,
    this.utcOffsetMinutes,
    this.freshness = PresenceFreshness.fresh,
  });
  final double? cellLat;
  final double? cellLng;
  final String? city;
  final String? country;
  final int? utcOffsetMinutes;
  final PresenceFreshness freshness;

  factory PresenceArea.fromRow(Map<String, dynamic> r) => PresenceArea(
    cellLat: (r['cell_lat'] as num?)?.toDouble(),
    cellLng: (r['cell_lng'] as num?)?.toDouble(),
    city: r['city'] as String?,
    country: r['country'] as String?,
    utcOffsetMinutes: (r['utc_offset_minutes'] as num?)?.toInt(),
    // Anything unexpected is treated as the less certain state.
    freshness:
        r['freshness'] == 'fresh'
            ? PresenceFreshness.fresh
            : PresenceFreshness.fading,
  );
}

enum PresenceStatus { off, sharing, paused }

/// My own sharing state (self-facing; the partner never sees a reason).
@immutable
class PresenceState {
  const PresenceState(this.status, {this.pausedUntil});
  final PresenceStatus status;
  final DateTime? pausedUntil;
  bool get isOn => status != PresenceStatus.off;
}

/// What couple_map_presence returned: at most my area and my partner's.
@immutable
class CoupleMapPresence {
  const CoupleMapPresence({
    this.self,
    this.partner,
    this.distanceKm,
    this.together = false,
    this.state = const PresenceState(PresenceStatus.off),
  });
  final PresenceArea? self;
  final PresenceArea? partner;
  final int? distanceKm;
  final bool together;
  final PresenceState state;

  static const none = CoupleMapPresence();

  static CoupleMapPresence fromRows(List<Map<String, dynamic>> rows) {
    Map<String, dynamic>? selfRow;
    Map<String, dynamic>? partnerRow;
    for (final r in rows) {
      if (r['who'] == 'self') selfRow = r;
      if (r['who'] == 'partner') partnerRow = r;
    }
    if (selfRow == null) return none;
    // Any pause value means paused: 'infinity' ("until I resume") has no
    // end date, and an unreadable one must never read as sharing.
    final pausedRaw = selfRow['my_paused_until'] as String?;
    final pausedUntil = pausedRaw == null ? null : DateTime.tryParse(pausedRaw);
    return CoupleMapPresence(
      self: PresenceArea.fromRow(selfRow),
      partner: partnerRow == null ? null : PresenceArea.fromRow(partnerRow),
      distanceKm: (partnerRow?['distance_km'] as num?)?.toInt(),
      together: partnerRow?['together'] == true,
      state:
          pausedRaw != null
              ? PresenceState(PresenceStatus.paused, pausedUntil: pausedUntil)
              : const PresenceState(PresenceStatus.sharing),
    );
  }

  /// The distance card's data, or null when there's no honest answer.
  PartnerDistance? get partnerDistance {
    final p = partner;
    final km = distanceKm;
    if (p == null || km == null) return null;
    return PartnerDistance(
      km: km.toDouble(),
      partnerCity: p.city,
      partnerUtcOffsetMinutes: p.utcOffsetMinutes,
      together: together,
    );
  }
}
