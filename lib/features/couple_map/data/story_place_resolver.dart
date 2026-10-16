import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Why a lookup found no place.
enum StoryPlaceProblem {
  /// Denied, but the system would still show a prompt (a tap may ask).
  needsAsk,

  /// Denied for good, or still denied after asking: only Settings can fix
  /// it.
  noPermission,

  /// Location services are off for the whole phone (Attune may be allowed).
  servicesOff,

  /// No fix in time, or anything else failed.
  notFound,
}

/// What a lookup found: a place (possibly approximate), or why not.
@immutable
class StoryPlaceLookup {
  const StoryPlaceLookup.found(
    StoryPlaceDraft this.draft, {
    this.approximate = false,
  }) : problem = null;
  const StoryPlaceLookup.failed(StoryPlaceProblem this.problem)
    : draft = null,
      approximate = false;
  final StoryPlaceDraft? draft;

  /// iOS Precise Location (or Android fine location) is off: the place is
  /// a few kilometres wide at best.
  final bool approximate;
  final StoryPlaceProblem? problem;
}

/// Where the story is being posted from: a precise fix plus a
/// neighbourhood label. Called ONLY once the author turns the pin switch
/// on (or it starts on from their last choice): never otherwise (§3.3).
abstract class StoryPlaceResolver {
  /// [ask] lets the system permission prompt show. Only an explicit "on"
  /// tap asks; a remembered "on" at camera open never prompts (it would
  /// re-ask after a denial every time the camera opened).
  Future<StoryPlaceLookup> resolve({required bool ask});
}

class GeolocatorStoryPlaceResolver implements StoryPlaceResolver {
  @override
  Future<StoryPlaceLookup> resolve({required bool ask}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const StoryPlaceLookup.failed(StoryPlaceProblem.servicesOff);
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        if (!ask) {
          return const StoryPlaceLookup.failed(StoryPlaceProblem.needsAsk);
        }
        p = await Geolocator.requestPermission();
      }
      if (p != LocationPermission.whileInUse &&
          p != LocationPermission.always) {
        return const StoryPlaceLookup.failed(StoryPlaceProblem.noPermission);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: CoupleMapConfig.placeFixTimeout,
        ),
      );
      var approximate = false;
      try {
        approximate =
            await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced;
      } catch (_) {}
      String? neighbourhood;
      String? city;
      try {
        // The platform geocoder (Android Geocoder / iOS CLGeocoder): the
        // app calls no third-party HTTP API, though the OS may ask Google
        // or Apple.
        final marks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        ).timeout(const Duration(seconds: 10));
        final m = marks.isEmpty ? null : marks.first;
        neighbourhood = m?.subLocality;
        city =
            (m?.locality?.isNotEmpty ?? false)
                ? m!.locality
                : m?.subAdministrativeArea;
      } catch (_) {}
      final draft = StoryPlaceDraft(
        lat: pos.latitude,
        lng: pos.longitude,
        label: placeLabel(neighbourhood: neighbourhood, city: city),
      );
      return draft.isValid
          ? StoryPlaceLookup.found(draft, approximate: approximate)
          : const StoryPlaceLookup.failed(StoryPlaceProblem.notFound);
    } catch (_) {
      return const StoryPlaceLookup.failed(StoryPlaceProblem.notFound);
    }
  }
}
