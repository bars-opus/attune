import 'dart:async';

import 'package:attune/core/services/location_service.dart';
import 'package:attune/core/utils/location/models/parsed_address.dart';
import 'package:attune/features/location/data/presence_gateway.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/presence_config.dart';
import 'package:flutter/foundation.dart';

/// Ambient presence for one couple, through the presence RPCs only.
///
/// The client writes its own (server-snapped) area and reads at most the
/// partner's cell — never a raw position, never a time. Nothing here logs a
/// coordinate or a place name (checklist 4.4).
class PresenceRepository {
  PresenceRepository(
    this._gateway,
    this._sampler,
    this._timezone, {
    LocationService? placeService,
    DateTime Function()? now,
  }) : _placeService = placeService ?? LocationService(),
       _now = now ?? DateTime.now;

  final PresenceGateway _gateway;
  final PresenceSampler _sampler;
  final Future<String> Function() _timezone;
  final LocationService _placeService;
  final DateTime Function() _now;

  /// Last successful automatic record, per couple (client debounce).
  final _lastRecordedAt = <String, DateTime>{};

  void _log(String what, Object e) =>
      debugPrint('presence: $what failed (${e.runtimeType})');

  /// Opting in: create the row, ask for permission once, then record.
  Future<void> startSharing(String relationshipId) async {
    await _gateway.rpc(
      'start_presence',
      params: {'p_relationship_id': relationshipId},
    );
    await _sampler.requestPermission();
    await record(relationshipId, force: true);
  }

  /// Records my area if I can get a fix; false otherwise. Never throws.
  ///
  /// Automatic calls within [PresenceConfig.recordDebounce] of the last
  /// success are skipped before sampling: the server would ignore the
  /// write, and each one costs a fix and a geocode (checklist 3.7).
  Future<bool> record(String relationshipId, {bool force = false}) async {
    final last = _lastRecordedAt[relationshipId];
    if (!force &&
        last != null &&
        _now().difference(last) < PresenceConfig.recordDebounce) {
      return false;
    }
    final s = await _sampler.sample();
    if (s == null) return false;
    try {
      await _gateway.rpc(
        'record_presence',
        params: {
          'p_relationship_id': relationshipId,
          'p_lat': s.lat,
          'p_lng': s.lng,
          'p_accuracy_m': s.accuracyM,
          'p_city': s.city,
          'p_country': s.country,
          'p_country_code': s.countryCode,
          'p_timezone': await _timezone(),
        },
      );
      _lastRecordedAt[relationshipId] = _now();
      return true;
    } catch (e) {
      _log('record', e);
      return false;
    }
  }

  /// Pauses for [forHowLong], or until resumed when null.
  Future<void> pause(String relationshipId, Duration? forHowLong) =>
      _gateway.rpc(
        'set_presence_pause',
        params: {
          'p_relationship_id': relationshipId,
          'p_until':
              forHowLong == null
                  ? 'infinity'
                  : DateTime.now().toUtc().add(forHowLong).toIso8601String(),
        },
      );

  /// Resuming needs a fresh sample (spec §4.2), so the debounce resets.
  Future<void> resume(String relationshipId) async {
    _lastRecordedAt.remove(relationshipId);
    await _gateway.rpc(
      'set_presence_pause',
      params: {'p_relationship_id': relationshipId, 'p_until': null},
    );
  }

  /// Turning it off deletes the row; the partner is not told.
  Future<void> stopSharing(String relationshipId) async {
    _lastRecordedAt.remove(relationshipId);
    await _gateway.rpc(
      'stop_presence',
      params: {'p_relationship_id': relationshipId},
    );
  }

  /// What the couple map may show.
  ///
  /// A failed read throws (after a PII-free log line) rather than returning
  /// [CoupleMapPresence.none]: "couldn't read" must never look like "not
  /// sharing", or the privacy toggle would show Off while sharing is on.
  Future<CoupleMapPresence> fetchMapPresence(String relationshipId) async {
    try {
      final rows = await _gateway.rpc(
        'couple_map_presence',
        params: {'p_relationship_id': relationshipId},
      );
      if (rows is! List) {
        throw StateError('couple_map_presence returned ${rows.runtimeType}');
      }
      return CoupleMapPresence.fromRows([
        for (final r in rows) Map<String, dynamic>.from(r as Map),
      ]);
    } catch (e) {
      _log('read', e);
      rethrow;
    }
  }

  /// Shares where you are, right now, on purpose (full precision: chosen).
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
      await _gateway.rpc(
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
    } catch (e) {
      _log('place update', e);
      return false;
    }
  }

  /// Where the user is now, for pre-filling a place update.
  Future<ParsedAddress?> currentPlace() async {
    try {
      return await _placeService.getCurrentLocationWithDetails().timeout(
        const Duration(seconds: 30),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }
}
