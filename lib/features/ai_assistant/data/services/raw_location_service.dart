// lib/features/ai_assistant/data/services/raw_location_service.dart
//
// A raw, coordinates-only position reader for the Nearby flow (AI
// Assistant spec §5.2). This is a DELIBERATELY separate, minimal
// service from `lib/core/services/location_service.dart` —
// `LocationService.getCurrentLocation()` internally calls
// `getCurrentLocationWithDetails()`, which reverse-geocodes the fix
// into a full street address/locality via `geocoding`'s
// `placemarkFromCoordinates`. Nearby's whole privacy story (spec §5.2:
// the server, not the client, ever resolves a fix into a place name;
// the client only ever forwards three numbers) breaks if this service
// ever routes through that method or its reverse-geocoding helpers —
// so `RawLocationService` calls `Geolocator` directly and imports
// nothing from `location_service.dart` or the `geocoding` package.
//
// Returns a typed [RawPositionResult] rather than a nullable
// `Position?` or a thrown exception: permission-denied,
// services-disabled, and platform-failure are all real, expected
// outcomes the Nearby sheet must render distinctly (a disclosure-then-
// retry prompt, a "turn on location services" prompt, and a generic
// retry, respectively) — not a crash and not a silent null the caller
// has to guess the reason for.
library;

import 'package:geolocator/geolocator.dart';

/// The outcome of [RawLocationService.getCurrentPosition]. Sealed so
/// every call site must handle each case explicitly rather than
/// treating "no position" as one undifferentiated failure.
sealed class RawPositionResult {
  const RawPositionResult();
}

/// A resolved fix. Deliberately has ONLY these three fields — no
/// address, locality, or place name of any kind. This is the type-
/// level proof the brief asks for: there is no field here a future
/// change could accidentally populate with a reverse-geocoded value,
/// because reverse geocoding has no output slot to write into.
class RawPositionSuccess extends RawPositionResult {
  final double latitude;
  final double longitude;
  final double accuracyM;

  const RawPositionSuccess({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
  });
}

/// The user declined (or has permanently denied) the location
/// permission prompt. Not an exception — declining is an expected,
/// first-class outcome the Nearby sheet must be able to return from
/// without ever having called the AI Assistant repository (spec §5.2's
/// "declining consumes no quota" guarantee lives one layer up, in the
/// sheet, but it depends on this type existing so the sheet has
/// something other than a thrown `PermissionDeniedException` to branch
/// on).
class RawPositionDenied extends RawPositionResult {
  const RawPositionDenied();
}

/// Device-level location services are turned off entirely (distinct
/// from the app-level permission being denied — this is "Location
/// Services" being off in system settings).
class RawPositionServiceDisabled extends RawPositionResult {
  const RawPositionServiceDisabled();
}

/// The platform call itself failed (timeout, transient platform
/// exception, etc.) after permission was granted and services were
/// enabled.
class RawPositionFailure extends RawPositionResult {
  const RawPositionFailure();
}

/// How long to wait for a fix before giving up. Nearby is a
/// user-initiated, in-the-moment request (the user is actively waiting
/// on this sheet, unlike `PresenceRepository`'s ambient background
/// read), but an unbounded wait can still hang the sheet indefinitely
/// on a poor fix — bounded here for the same reason
/// `PresenceRepository._fixTimeout` bounds its own read.
const _fixTimeout = Duration(seconds: 20);

/// Nearby-only raw position reader. Never reverse-geocodes; never
/// calls `LocationService`.
class RawLocationService {
  const RawLocationService();

  /// Requests balanced/approximate accuracy (spec §5.2: "not
  /// high-accuracy tracking") — `LocationAccuracy.medium`, not `.high`
  /// or `.best`. Nearby needs "which neighborhood/city" precision for a
  /// places search, not turn-by-turn precision.
  Future<RawPositionResult> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const RawPositionServiceDisabled();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const RawPositionDenied();
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(_fixTimeout);
      return RawPositionSuccess(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
      );
    } catch (_) {
      return const RawPositionFailure();
    }
  }
}
