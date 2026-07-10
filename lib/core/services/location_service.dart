import 'dart:convert';
import 'dart:math' as math;

import 'package:attune/core/utils/location/models/parsed_address.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:attune/core/config/env.dart';
import 'package:attune/core/utils/location/location_search_mode.dart';

class LocationService {
  String get _mapboxToken => Environment.mapboxAccessToken;
  String get _googleApiKey => Environment.googleMapsApiKey;

  static const String _mapboxGeocodingBaseUrl =
      'https://api.mapbox.com/geocoding/v5/mapbox.places';
  static const String _placesAutocompleteUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String _placesDetailsUrl =
      'https://maps.googleapis.com/maps/api/place/details/json';
  static const String _geocodingUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';

  /// Returns autocomplete suggestions using Google Places API.
  ///
  /// Suggestions come back instantly with a [placeId] but without coordinates —
  /// call [getPlaceDetails] when the user taps a result to resolve coordinates.
  ///
  /// [mode] controls the Places `types` filter:
  ///  - [LocationSearchMode.city]    → (cities) for client discovery location
  ///  - [LocationSearchMode.address] → geocode (addresses + neighbourhoods like "Community 11")
  ///
  /// [proximityLat] / [proximityLng] bias results toward a known area.
  Future<List<ParsedAddress>> getLocationSuggestions(
    String query, {
    LocationSearchMode mode = LocationSearchMode.city,
    double? proximityLng,
    double? proximityLat,
  }) async {
    if (query.length < 2) return [];

    final types = mode == LocationSearchMode.address ? 'geocode' : '(cities)';

    final params = {
      'input': query,
      'key': _googleApiKey,
      'types': types,
      'language': 'en',
      if (proximityLat != null && proximityLng != null)
        'location': '$proximityLat,$proximityLng',
      if (proximityLat != null && proximityLng != null) 'radius': '50000',
    };

    try {
      final url = Uri.parse(_placesAutocompleteUrl).replace(
        queryParameters: params,
      );

      if (kDebugMode) {
        debugPrint(
          'Places Autocomplete: ${url.toString().replaceFirst(_googleApiKey, 'HIDDEN')}',
        );
      }

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';

        if (status != 'OK' && status != 'ZERO_RESULTS') {
          if (kDebugMode) debugPrint('Places Autocomplete status: $status');
          return [];
        }

        final predictions = data['predictions'] as List? ?? [];
        return predictions.map((p) {
          final description = p['description'] as String? ?? '';
          final placeId = p['place_id'] as String? ?? '';
          final structured = p['structured_formatting'] as Map? ?? {};
          final mainText = structured['main_text'] as String? ?? '';
          final secondaryText = structured['secondary_text'] as String?;

          return ParsedAddress(
            fullAddress: description,
            city: secondaryText,
            street: mainText,
            placeId: placeId.isNotEmpty ? placeId : null,
          );
        }).toList();
      } else {
        if (kDebugMode) {
          debugPrint('Places Autocomplete HTTP ${response.statusCode}');
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Places Autocomplete error: $e');
      return [];
    }
  }

  /// Resolves a Google Places [placeId] to a full [ParsedAddress] with coordinates.
  /// Call this when the user taps an autocomplete suggestion.
  Future<ParsedAddress?> getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(_placesDetailsUrl).replace(
        queryParameters: {
          'place_id': placeId,
          'fields': 'formatted_address,geometry,address_components,name',
          'key': _googleApiKey,
          'language': 'en',
        },
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        if (status != 'OK') return null;

        final result = data['result'] as Map<String, dynamic>? ?? {};
        final formattedAddress = result['formatted_address'] as String? ?? '';
        final geometry = result['geometry'] as Map? ?? {};
        final location = geometry['location'] as Map? ?? {};
        final lat = (location['lat'] as num?)?.toDouble();
        final lng = (location['lng'] as num?)?.toDouble();

        String? street, city, state, country, postalCode, countryCode;

        for (final component in result['address_components'] as List? ?? []) {
          final types = (component['types'] as List).cast<String>();
          final longName = component['long_name'] as String? ?? '';
          final shortName = component['short_name'] as String? ?? '';

          if (types.contains('route')) street = longName;
          if (types.contains('locality') ||
              types.contains('sublocality_level_1')) {
            city ??= longName;
          }
          if (types.contains('administrative_area_level_1')) state = longName;
          if (types.contains('country')) {
            country = longName;
            countryCode = shortName;
          }
          if (types.contains('postal_code')) postalCode = longName;
        }

        return ParsedAddress(
          fullAddress: formattedAddress,
          street: street,
          city: city,
          state: state,
          postalCode: postalCode,
          country: country,
          countryCode: countryCode,
          latitude: lat,
          longitude: lng,
          placeId: placeId,
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Places Details error: $e');
      return null;
    }
  }

  /// Forward geocoding via Google Geocoding API.
  /// Used when the user types a query and taps the Search button directly.
  Future<ParsedAddress?> getParsedAddressFromQueryGoogle(String query) async {
    try {
      final url = Uri.parse(_geocodingUrl).replace(
        queryParameters: {
          'address': query,
          'key': _googleApiKey,
          'language': 'en',
        },
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        if (status != 'OK') return null;

        final results = data['results'] as List? ?? [];
        if (results.isEmpty) return null;

        final result = results.first as Map<String, dynamic>;
        final formattedAddress = result['formatted_address'] as String? ?? '';
        final geometry = result['geometry'] as Map? ?? {};
        final location = geometry['location'] as Map? ?? {};
        final lat = (location['lat'] as num?)?.toDouble();
        final lng = (location['lng'] as num?)?.toDouble();

        String? street, city, state, country, postalCode, countryCode;

        for (final component in result['address_components'] as List? ?? []) {
          final types = (component['types'] as List).cast<String>();
          final longName = component['long_name'] as String? ?? '';
          final shortName = component['short_name'] as String? ?? '';

          if (types.contains('route')) street = longName;
          if (types.contains('locality') ||
              types.contains('sublocality_level_1')) {
            city ??= longName;
          }
          if (types.contains('administrative_area_level_1')) state = longName;
          if (types.contains('country')) {
            country = longName;
            countryCode = shortName;
          }
          if (types.contains('postal_code')) postalCode = longName;
        }

        return ParsedAddress(
          fullAddress: formattedAddress,
          street: street,
          city: city,
          state: state,
          postalCode: postalCode,
          country: country,
          countryCode: countryCode,
          latitude: lat,
          longitude: lng,
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Google Geocoding error: $e');
      return null;
    }
  }

  /// Reverse geocoding using Mapbox (kept for map-side use)
  Future<ParsedAddress?> getAddressFromCoordinatesWithMapbox({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final url = Uri.parse(
        '$_mapboxGeocodingBaseUrl/$longitude,$latitude.json'
        '?access_token=$_mapboxToken'
        '&types=address,place,locality'
        '&limit=1',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List? ?? [];

        if (features.isNotEmpty) {
          final feature = features.first;
          final placeName = feature['place_name'] as String? ?? '';
          final coordinates = feature['geometry']['coordinates'] as List?;

          if (coordinates != null && coordinates.length >= 2) {
            final lng = (coordinates[0] as num).toDouble();
            final lat = (coordinates[1] as num).toDouble();

            final context = feature['context'] as List? ?? [];
            String? city, state, country, countryCode, street, postalCode;

            for (final component in context) {
              final id = component['id'] as String? ?? '';
              final text = component['text'] as String? ?? '';

              if (id.contains('place')) city = text;
              if (id.contains('region')) state = text;
              if (id.contains('country')) {
                country = text;
                // Mapbox provides ISO 3166-1 alpha-2 code directly in short_code
                // (e.g., "ng" for Nigeria). Use it directly rather than the
                // manual name→code lookup which only covers ~20 countries.
                final raw = component['short_code'] as String?;
                countryCode = raw != null ? raw.toUpperCase() : _mapCountryToCode(text);
              }
              if (id.contains('postcode')) postalCode = text;
            }

            street =
                feature['text'] as String? ?? feature['address'] as String?;

            return ParsedAddress(
              fullAddress: placeName,
              street: street,
              city: city,
              state: state,
              postalCode: postalCode,
              country: country,
              countryCode: countryCode,
              latitude: lat,
              longitude: lng,
            );
          }
        }
      }

      return await getParsedAddressFromCoordinates(latitude, longitude);
    } catch (e) {
      print('Mapbox reverse geocoding error: $e');
      return await getParsedAddressFromCoordinates(latitude, longitude);
    }
  }

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check and request location permission
  Future<bool> requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Get current device location with full address details
  Future<ParsedAddress?> getCurrentLocationWithDetails() async {
    try {
      // Check if service is enabled
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      // Check permission
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        throw Exception('Location permission denied');
      }

      // Get position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get address details from coordinates
      return await _getParsedAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );
    } catch (e) {
      return null;
    }
  }

  /// Get current device location (legacy method - returns Position only)
  Future<Position?> getCurrentLocation() async {
    try {
      final address = await getCurrentLocationWithDetails();
      if (address == null) return null;

      return Position(
        latitude: address.latitude!,
        longitude: address.longitude!,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    } catch (e) {
      return null;
    }
  }

  /// Get address from coordinates (reverse geocoding) with full details
  Future<ParsedAddress?> getParsedAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    return _getParsedAddressFromCoordinates(latitude, longitude);
  }

  /// Internal method to get parsed address from coordinates.
  /// Always returns a [ParsedAddress] with valid coordinates — even if reverse
  /// geocoding fails — so GPS lat/lng are never silently lost.
  Future<ParsedAddress?> _getParsedAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        final addressParts = <String>[];
        if (place.street != null) addressParts.add(place.street!);
        if (place.locality != null) addressParts.add(place.locality!);
        if (place.administrativeArea != null)
          addressParts.add(place.administrativeArea!);
        if (place.country != null) addressParts.add(place.country!);
        final fullAddress =
            addressParts.isNotEmpty ? addressParts.join(', ') : _coordFallbackName(latitude, longitude);

        return ParsedAddress(
          fullAddress: fullAddress,
          street: place.street,
          city: place.locality,
          state: place.administrativeArea,
          postalCode: place.postalCode,
          country: place.country,
          // isoCountryCode is provided directly by the platform geocoder (CLGeocoder
          // on iOS, Android Geocoder on Android) — far more reliable than the manual
          // country-name → ISO-code lookup table which only covers ~20 countries.
          countryCode: place.isoCountryCode ?? _mapCountryToCode(place.country),
          latitude: latitude,
          longitude: longitude,
        );
      }
      // Geocoding returned no placemarks — still keep the coordinates.
      return ParsedAddress(
        fullAddress: _coordFallbackName(latitude, longitude),
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      // Geocoding threw (network error, quota, etc.) — still keep coordinates.
      return ParsedAddress(
        fullAddress: _coordFallbackName(latitude, longitude),
        latitude: latitude,
        longitude: longitude,
      );
    }
  }

  String _coordFallbackName(double lat, double lng) =>
      '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';

  /// Get address from coordinates (legacy method - returns String only)
  Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    final parsed = await _getParsedAddressFromCoordinates(latitude, longitude);
    return parsed?.fullAddress;
  }

  /// Get coordinates from address (forward geocoding) with full details
  Future<ParsedAddress?> getParsedAddressFromQuery(String query) async {
    try {
      List<Location> locations = await locationFromAddress(query);

      if (locations.isNotEmpty) {
        final loc = locations.first;
        return await _getParsedAddressFromCoordinates(
          loc.latitude,
          loc.longitude,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get coordinates from address (legacy method - returns Position only)
  Future<Position?> getCoordinatesFromAddress(String address) async {
    try {
      final parsed = await getParsedAddressFromQuery(address);
      if (parsed == null) return null;

      return Position(
        latitude: parsed.latitude!,
        longitude: parsed.longitude!,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    } catch (e) {
      return null;
    }
  }

  /// Calculate distance between two coordinates (in km)
  // In your LocationService class
  // In your LocationService class
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371;

    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double distance = earthRadiusKm * c;

    return distance;
  }

  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  /// Get distance in meters (more precise for short distances)
  double calculateDistanceInMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return calculateDistance(lat1, lon1, lat2, lon2) * 1000;
  }

  /// Get estimated travel time
  String getEstimatedTravelTime(double distanceKm, String mode) {
    final double speedKmh =
        mode == 'car' ? 40.0 : 5.0; // Car: 40 km/h, Walking: 5 km/h
    final double hours = distanceKm / speedKmh;
    final int minutes = (hours * 60).round();

    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} hr ${minutes % 60} min';
  }

  /// Last-resort fallback: map country name → ISO 3166-1 alpha-2 code.
  /// Prefer platform-native isoCountryCode (geocoding) or Mapbox short_code —
  /// this is only reached when neither is available.
  String? _mapCountryToCode(String? countryName) {
    if (countryName == null) return null;

    const Map<String, String> countryCodeMap = {
      // North America
      'United States': 'US',
      'USA': 'US',
      'United States of America': 'US',
      'Canada': 'CA',
      'Mexico': 'MX',

      // Europe
      'United Kingdom': 'GB',
      'UK': 'GB',
      'Great Britain': 'GB',
      'France': 'FR',
      'Germany': 'DE',
      'Italy': 'IT',
      'Spain': 'ES',
      'Netherlands': 'NL',
      'Belgium': 'BE',
      'Sweden': 'SE',
      'Switzerland': 'CH',
      'Poland': 'PL',
      'Portugal': 'PT',
      'Russia': 'RU',
      'Ukraine': 'UA',
      'Norway': 'NO',
      'Denmark': 'DK',
      'Finland': 'FI',
      'Austria': 'AT',
      'Greece': 'GR',
      'Czech Republic': 'CZ',
      'Romania': 'RO',
      'Hungary': 'HU',
      'Ireland': 'IE',

      // Oceania
      'Australia': 'AU',
      'New Zealand': 'NZ',

      // East Asia
      'Japan': 'JP',
      'China': 'CN',
      'South Korea': 'KR',
      'Taiwan': 'TW',
      'Hong Kong': 'HK',

      // South Asia
      'India': 'IN',
      'Pakistan': 'PK',
      'Bangladesh': 'BD',
      'Sri Lanka': 'LK',
      'Nepal': 'NP',

      // Southeast Asia
      'Indonesia': 'ID',
      'Philippines': 'PH',
      'Vietnam': 'VN',
      'Thailand': 'TH',
      'Malaysia': 'MY',
      'Singapore': 'SG',
      'Myanmar': 'MM',

      // Middle East
      'United Arab Emirates': 'AE',
      'UAE': 'AE',
      'Saudi Arabia': 'SA',
      'Qatar': 'QA',
      'Kuwait': 'KW',
      'Bahrain': 'BH',
      'Oman': 'OM',
      'Jordan': 'JO',
      'Lebanon': 'LB',
      'Israel': 'IL',
      'Turkey': 'TR',
      'Iran': 'IR',
      'Iraq': 'IQ',

      // North Africa
      'Egypt': 'EG',
      'Morocco': 'MA',
      'Tunisia': 'TN',
      'Algeria': 'DZ',
      'Libya': 'LY',

      // West Africa
      'Nigeria': 'NG',
      'Ghana': 'GH',
      'Senegal': 'SN',
      'Ivory Coast': 'CI',
      "Côte d'Ivoire": 'CI',
      'Cameroon': 'CM',
      'Mali': 'ML',
      'Burkina Faso': 'BF',
      'Benin': 'BJ',
      'Togo': 'TG',
      'Sierra Leone': 'SL',
      'Liberia': 'LR',
      'Guinea': 'GN',
      'Guinea-Bissau': 'GW',
      'Gambia': 'GM',
      'Mauritania': 'MR',
      'Niger': 'NE',

      // East Africa
      'Kenya': 'KE',
      'Ethiopia': 'ET',
      'Tanzania': 'TZ',
      'Uganda': 'UG',
      'Rwanda': 'RW',
      'Burundi': 'BI',
      'Somalia': 'SO',
      'Eritrea': 'ER',
      'Djibouti': 'DJ',
      'South Sudan': 'SS',
      'Sudan': 'SD',

      // Central Africa
      'Democratic Republic of the Congo': 'CD',
      'DRC': 'CD',
      'Congo': 'CG',
      'Republic of the Congo': 'CG',
      'Central African Republic': 'CF',
      'Chad': 'TD',
      'Gabon': 'GA',
      'Equatorial Guinea': 'GQ',
      'São Tomé and Príncipe': 'ST',

      // Southern Africa
      'South Africa': 'ZA',
      'Zimbabwe': 'ZW',
      'Zambia': 'ZM',
      'Mozambique': 'MZ',
      'Angola': 'AO',
      'Namibia': 'NA',
      'Botswana': 'BW',
      'Madagascar': 'MG',
      'Malawi': 'MW',
      'Lesotho': 'LS',
      'Eswatini': 'SZ',
      'Swaziland': 'SZ',
      'Comoros': 'KM',
      'Mauritius': 'MU',
      'Seychelles': 'SC',

      // South America
      'Brazil': 'BR',
      'Argentina': 'AR',
      'Chile': 'CL',
      'Colombia': 'CO',
      'Peru': 'PE',
      'Venezuela': 'VE',
      'Ecuador': 'EC',
      'Bolivia': 'BO',
      'Paraguay': 'PY',
      'Uruguay': 'UY',
    };

    // Exact match first
    if (countryCodeMap.containsKey(countryName)) {
      return countryCodeMap[countryName];
    }

    // Case-insensitive fallback
    final lowerName = countryName.toLowerCase();
    for (final entry in countryCodeMap.entries) {
      if (entry.key.toLowerCase() == lowerName) {
        return entry.value;
      }
    }

    return null;
  }
}
