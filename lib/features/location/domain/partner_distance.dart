import 'package:flutter/foundation.dart';

/// What the distance row says, chosen from the distance itself.
///
/// A single format cannot serve this feature. "5,100 km" is fine once and
/// then becomes a daily reminder of absence for exactly the couples it is
/// meant for -- a static large number measures how far apart you are, it
/// does not make anyone feel closer. So the row shows what CHANGES when
/// distance does not: their local time, a countdown to a shared trip, or
/// how much the distance moved.
enum DistanceTone {
  /// Close enough that a number is the least interesting thing to say.
  together,

  /// Same city: minutes, not kilometres.
  nearby,

  /// Same country: a journey, described as one.
  sameCountry,

  /// Far apart, with a trip in the shared calendar. The countdown replaces
  /// the distance entirely.
  countdown,

  /// Far apart with nothing booked. The hardest case, and the one the
  /// long-distance couple lives in.
  distant,

  /// Someone is travelling. The delta is the interesting number and it
  /// appears exactly when something meaningful is happening.
  closing,
}

@immutable
class PartnerDistance {
  const PartnerDistance({
    required this.km,
    this.partnerCity,
    this.partnerTimezone,
    this.partnerLocalTime,
    this.daysUntilTogether,
    this.kmClosedSinceYesterday,
    this.updatedAt,
  });

  final double km;
  final String? partnerCity;
  final String? partnerTimezone;
  final DateTime? partnerLocalTime;

  /// Days until a calendar event both partners attend. Turns a standing
  /// distance into a countdown, which is the same data with the opposite
  /// emotional valence.
  final int? daysUntilTogether;

  /// Positive when they are closer than yesterday.
  final double? kmClosedSinceYesterday;

  final DateTime? updatedAt;

  /// Below this, a distance is noise -- GPS drift alone moves this far.
  static const togetherKm = 1.0;
  static const nearbyKm = 50.0;
  static const sameCountryKm = 800.0;

  /// A change worth remarking on. Below this it is commuting, not
  /// travelling, and calling it out would make ordinary movement visible
  /// -- which is precisely what the coarse distance exists to avoid.
  static const notableChangeKm = 100.0;

  DistanceTone get tone {
    if (km < togetherKm) return DistanceTone.together;

    final closed = kmClosedSinceYesterday;
    if (closed != null && closed.abs() >= notableChangeKm) {
      return DistanceTone.closing;
    }

    if (km < nearbyKm) return DistanceTone.nearby;
    if (km < sameCountryKm) return DistanceTone.sameCountry;
    if (daysUntilTogether != null) return DistanceTone.countdown;
    return DistanceTone.distant;
  }
}

/// How you would actually cross this distance.
///
/// Named for how it FEELS rather than for a routing engine's answer: this
/// is a couple's ambient sense of separation, not a journey planner.
enum TravelMode { walk, drive, fly }

TravelMode travelModeFor(double km) {
  if (km <= 2) return TravelMode.walk;
  if (km <= PartnerDistance.sameCountryKm) return TravelMode.drive;
  return TravelMode.fly;
}

/// Rough travel time, deliberately coarse.
///
/// Rounded to five minutes under an hour and to whole hours above, so the
/// row cannot be read as movement. A number that twitches every refresh is
/// a movement sensor; one that changes about once an hour is a fact about
/// the day.
Duration travelTimeFor(double km, TravelMode mode) {
  final hours = switch (mode) {
    TravelMode.walk => km / 5,
    TravelMode.drive => km / 50,
    // Includes a flat allowance for getting to and through an airport,
    // because "1 hour by air" for a flight you spend a day reaching is a
    // worse answer than a rounder, truer one.
    TravelMode.fly => 3 + km / 800,
  };

  final minutes = (hours * 60).round();
  if (minutes < 60) {
    return Duration(minutes: (minutes / 5).round().clamp(1, 12) * 5);
  }
  return Duration(hours: (minutes / 60).round());
}
