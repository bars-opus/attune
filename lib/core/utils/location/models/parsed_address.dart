import 'package:equatable/equatable.dart';

/// Represents a parsed address with its components
class ParsedAddress extends Equatable {
  final String fullAddress;
  final String? street;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
  final String? countryCode; // ISO 3166-1 alpha-2 (e.g., 'US', 'GB', 'FR')
  final double? latitude;
  final double? longitude;
  /// Google Places place_id — set when the address came from Places Autocomplete.
  /// Coordinates are resolved lazily via Places Details when the user taps.
  final String? placeId;

  const ParsedAddress({
    required this.fullAddress,
    this.street,
    this.city,
    this.state,
    this.postalCode,
    this.country,
    this.countryCode,
    this.latitude,
    this.longitude,
    this.placeId,
  });

  /// Create from coordinates (reverse geocoding)
  factory ParsedAddress.fromCoordinates({
    required double latitude,
    required double longitude,
    String? fullAddress,
    String? city,
    String? country,
    String? countryCode,
  }) {
    return ParsedAddress(
      fullAddress: fullAddress ?? '$latitude, $longitude',
      city: city,
      country: country,
      countryCode: countryCode,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  List<Object?> get props => [
    fullAddress,
    street,
    city,
    state,
    postalCode,
    country,
    countryCode,
    latitude,
    longitude,
    placeId,
  ];
}
