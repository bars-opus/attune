import 'dart:convert';

import 'package:attune/core/utils/location/models/parsed_address.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/core/utils/location/models/user_location.dart';
import 'package:attune/features/currency/domain/entities/currency.dart';
import 'package:attune/features/currency/domain/mappers/country_currency_mapper.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attune/core/services/location_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'location_provider.g.dart';

/// Storage keys

const String _kStoredLocationKey = 'stored_user_location';
const String _kStoredCurrencyKey = 'stored_user_currency';

@riverpod
LocationService locationService(LocationServiceRef ref) {
  return LocationService();
}

@riverpod
class UserLocationNotifier extends _$UserLocationNotifier {
  @override
  UserLocation? build() {
    _loadSavedLocation();
    return null;
  }

  Future<void> _loadSavedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final storedJson = prefs.getString(_kStoredLocationKey);

    if (storedJson != null) {
      try {
        final location = UserLocation.fromJson(
          Map<String, dynamic>.from(jsonDecode(storedJson) as Map),
        );
        state = location;
        return;
      } catch (e) {
        // Invalid stored data, ignore
      }
    }

    // If user is logged in, try Supabase
    final user = ref.read(currentUserProvider);
    if (user != null) {
      try {
        final response =
            await Supabase.instance.client
                .from('profiles')
                .select('preferred_location')
                .eq('id', user.id)
                .maybeSingle();

        if (response != null && response['preferred_location'] != null) {
          final location = UserLocation.fromJson(
            response['preferred_location'] as Map<String, dynamic>,
          );
          state = location;

          await prefs.setString(
            _kStoredLocationKey,
            jsonEncode(location.toJson()),
          );
        }
      } catch (e) {
        print('Error loading location from Supabase: $e');
      }
    }
  }

  Future<bool> setCurrentLocation() async {
    final service = ref.read(locationServiceProvider);

    try {
      // Use your existing method that returns ParsedAddress with countryCode
      final parsedAddress = await service.getCurrentLocationWithDetails();
      if (parsedAddress == null) return false;

      // Auto-detect currency from country code
      Currency? detectedCurrency;
      if (parsedAddress.countryCode != null) {
        detectedCurrency = CountryCurrencyMapper.getPrimaryCurrency(
          parsedAddress.countryCode,
        );
      }

      final location = UserLocation(
        displayName: parsedAddress.fullAddress,
        latitude: parsedAddress.latitude!,
        longitude: parsedAddress.longitude!,
        source: LocationSource.current,
        timestamp: DateTime.now(),
        currencyCode: detectedCurrency?.code,
        currencySymbol: detectedCurrency?.symbol,
      );

      await _saveLocation(location);
      state = location;
      return true;
    } catch (e) {
      print('Error setting current location: $e');
      return false;
    }
  }

  Future<bool> setSearchedLocation(String query) async {
    final service = ref.read(locationServiceProvider);

    try {
      // Use your existing method that returns ParsedAddress with countryCode
      final parsedAddress = await service.getParsedAddressFromQuery(query);
      if (parsedAddress == null) return false;

      // Auto-detect currency from country code
      Currency? detectedCurrency;
      if (parsedAddress.countryCode != null) {
        detectedCurrency = CountryCurrencyMapper.getPrimaryCurrency(
          parsedAddress.countryCode,
        );
      }

      final location = UserLocation(
        displayName: parsedAddress.fullAddress,
        latitude: parsedAddress.latitude!,
        longitude: parsedAddress.longitude!,
        source: LocationSource.search,
        timestamp: DateTime.now(),
        currencyCode: detectedCurrency?.code,
        currencySymbol: detectedCurrency?.symbol,
      );

      await _saveLocation(location);
      state = location;
      return true;
    } catch (e) {
      print('Error setting searched location: $e');
      return false;
    }
  }

  /// Set location directly from an already-resolved [ParsedAddress].
  /// Avoids re-geocoding when the caller already has coordinates (e.g. from
  /// Google Places Details or GPS).
  Future<bool> setFromParsedAddress(ParsedAddress parsedAddress) async {
    if (parsedAddress.latitude == null || parsedAddress.longitude == null) {
      return false;
    }

    Currency? detectedCurrency;
    if (parsedAddress.countryCode != null) {
      detectedCurrency = CountryCurrencyMapper.getPrimaryCurrency(
        parsedAddress.countryCode,
      );
    }

    final location = UserLocation(
      displayName: parsedAddress.city ?? parsedAddress.fullAddress,
      latitude: parsedAddress.latitude!,
      longitude: parsedAddress.longitude!,
      source: LocationSource.search,
      timestamp: DateTime.now(),
      currencyCode: detectedCurrency?.code,
      currencySymbol: detectedCurrency?.symbol,
    );

    await _saveLocation(location);
    state = location;
    return true;
  }

  /// Update currency for the current location
  Future<void> updateCurrency(Currency currency) async {
    if (state == null) return;

    final updatedLocation = UserLocation(
      displayName: state!.displayName,
      latitude: state!.latitude,
      longitude: state!.longitude,
      source: state!.source,
      timestamp: DateTime.now(),
      currencyCode: currency.code,
      currencySymbol: currency.symbol,
    );

    await _saveLocation(updatedLocation);
    state = updatedLocation;
  }

  Future<void> _saveLocation(UserLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStoredLocationKey, jsonEncode(location.toJson()));

    final user = ref.read(currentUserProvider);
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('profiles')
            .update({
              'preferred_location': location.toJson(),
              'last_location_update': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id);
      } catch (e) {
        print('Error saving location to Supabase: $e');
      }
    }
  }

  Future<void> clearLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStoredLocationKey);

    final user = ref.read(currentUserProvider);
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('profiles')
            .update({'preferred_location': null})
            .eq('id', user.id);
      } catch (e) {
        print('Error clearing location from Supabase: $e');
      }
    }

    state = null;
  }
}

@riverpod
bool hasLocation(HasLocationRef ref) {
  return ref.watch(userLocationNotifierProvider) != null;
}

@riverpod
class DistanceToShop extends _$DistanceToShop {
  @override
  double? build(double shopLat, double shopLng) {
    final userLocation = ref.watch(userLocationNotifierProvider);
    if (userLocation == null) return null;

    final service = ref.read(locationServiceProvider);
    return service.calculateDistance(
      userLocation.latitude,
      userLocation.longitude,
      shopLat,
      shopLng,
    );
  }
}

@riverpod
class DistanceToFreelancer extends _$DistanceToFreelancer {
  @override
  double? build(double freelancerLat, double freelancerLng) {
    final userLocation = ref.watch(userLocationNotifierProvider);
    if (userLocation == null) return null;

    final service = ref.read(locationServiceProvider);
    return service.calculateDistance(
      userLocation.latitude,
      userLocation.longitude,
      freelancerLat,
      freelancerLng,
    );
  }
}
