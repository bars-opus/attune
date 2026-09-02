import 'dart:async';

import 'package:attune/core/services/location_service.dart';
import 'package:attune/core/utils/location/models/parsed_address.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads and writes location presence.
///
/// The asymmetry here is deliberate and load-bearing: this class WRITES a
/// position (the user's own, rounded) and READS a distance (never the
/// partner's position). There is no method that returns where the partner
/// is, because no such server function exists.
class PresenceRepository {
  PresenceRepository(this._supabase, this._locationService);

  final SupabaseClient _supabase;
  final LocationService _locationService;

  /// How coarse a stored position is: 3 decimal places, about 100m.
  ///
  /// Enough for "same city" and a travel time. Not enough to say which
  /// building, which is the point -- the ambient row must not be able to
  /// answer "where are they" even to someone reading the database.
  static const _precision = 3;

  double _round(double value) {
    final factor = 1000.0; // 10^_precision
    return (value * factor).round() / factor;
  }

  /// Records the user's own position.
  ///
  /// Returns false when location is unavailable or refused -- never
  /// throws, because presence is ambient and a failure to sample must not
  /// surface as an error in a chat screen.
  Future<bool> recordOwnPresence() async {
    try {
      final ParsedAddress? address =
          await _locationService.getCurrentLocationWithDetails();
      if (address?.latitude == null || address?.longitude == null) {
        return false;
      }

      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      await _supabase.from('partner_presence').upsert({
        'user_id': user.id,
        'latitude': _round(address!.latitude!),
        'longitude': _round(address.longitude!),
        'city': address.city,
        'country': address.country,
        'country_code': address.countryCode,
        'timezone': DateTime.now().timeZoneName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      return true;
    } catch (_) {
      return false;
    }
  }

  /// How far apart the couple is, or null.
  ///
  /// Null covers every case where the honest answer is "we don't know":
  /// either partner not sharing, a stale position, or a caller who is not
  /// a member. The UI shows nothing rather than a guess.
  Future<PartnerDistance?> fetchDistance(String relationshipId) async {
    try {
      final result = await _supabase.rpc(
        'partner_distance',
        params: {'p_relationship_id': relationshipId},
      );

      if (result is! List || result.isEmpty) return null;
      final row = Map<String, dynamic>.from(result.first as Map);

      final km = (row['distance_km'] as num?)?.toDouble();
      if (km == null) return null;

      return PartnerDistance(
        km: km,
        partnerCity: row['partner_city'] as String?,
        partnerTimezone: row['partner_timezone'] as String?,
        updatedAt: DateTime.tryParse(
          (row['partner_updated_at'] as String?) ?? '',
        )?.toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Stops sharing.
  ///
  /// DELETES the row rather than blanking a flag. Presence that is merely
  /// hidden is still presence, and the guarantee this feature makes is
  /// that turning it off leaves nothing behind. The partner is not
  /// notified: an exit that announces itself is not an exit.
  Future<void> stopSharing() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    await _supabase.from('partner_presence').delete().eq('user_id', user.id);
  }

  /// Shares where you are, right now, on purpose.
  ///
  /// Full precision, unlike ambient presence: the difference between
  /// being observed and telling someone is exactly that you chose to.
  Future<bool> postPlaceUpdate({
    required String relationshipId,
    required String label,
    String? note,
    double? latitude,
    double? longitude,
    String? city,
    String? country,
  }) async {
    try {
      await _supabase.rpc(
        'post_place_update',
        params: {
          'p_relationship_id': relationshipId,
          'p_label': label,
          'p_note': note,
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_city': city,
          'p_country': country,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Where the user is now, for pre-filling an update.
  Future<ParsedAddress?> currentPlace() async {
    try {
      return await _locationService.getCurrentLocationWithDetails();
    } catch (_) {
      return null;
    }
  }

  Future<bool> isSharing() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    final rows = await _supabase
        .from('partner_presence')
        .select('user_id')
        .eq('user_id', user.id)
        .limit(1);
    return rows.isNotEmpty;
  }
}
