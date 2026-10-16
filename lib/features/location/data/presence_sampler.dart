import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/domain/presence_config.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

@immutable
class PresenceSample {
  const PresenceSample({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    this.city,
    this.country,
    this.countryCode,
  });
  final double lat;
  final double lng;
  final double accuracyM;
  final String? city;
  final String? country;
  final String? countryCode;
}

/// Where the device roughly is, for ambient presence.
abstract class PresenceSampler {
  /// A low-accuracy fix plus an on-device place name, or null. Never asks
  /// for permission and never throws: presence is ambient.
  Future<PresenceSample?> sample();

  /// Asks for permission. Called only from an explicit opt-in tap.
  Future<bool> requestPermission();

  /// Whether a fix is possible right now. Never prompts.
  Future<LocationAccess> access();

  /// Opens the system settings where Attune's location can be turned on.
  Future<void> openSettings();
}

class GeolocatorPresenceSampler implements PresenceSampler {
  @override
  Future<PresenceSample?> sample() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return null;
      }
      // Medium: ~100 m from Wi-Fi/cell (Android BALANCED_POWER, no GPS),
      // enough for a ~1 km cell. Android's `low` is city-level (~10 km) and
      // would rarely pass the 2 km cutoff. The server snaps it either way.
      // (iOS shows its Precise switch on the permission prompt regardless.)
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: PresenceConfig.fixTimeout,
        ),
      );
      String? city;
      String? country;
      String? code;
      try {
        // The platform geocoder (Android Geocoder / iOS CLGeocoder): the app
        // calls no third-party HTTP API, though the OS may ask Google or Apple.
        final marks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        ).timeout(PresenceConfig.geocodeTimeout);
        final m = marks.isEmpty ? null : marks.first;
        city =
            m?.locality?.isNotEmpty == true
                ? m!.locality
                : m?.subAdministrativeArea;
        country = m?.country;
        code = m?.isoCountryCode;
      } catch (_) {}
      return PresenceSample(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracyM: pos.accuracy,
        city: city,
        country: country,
        countryCode: code,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      return p == LocationPermission.whileInUse ||
          p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<LocationAccess> access() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceOff;
      }
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.whileInUse ||
              p == LocationPermission.always
          ? LocationAccess.granted
          : LocationAccess.denied;
    } catch (_) {
      return LocationAccess.denied;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }
}
