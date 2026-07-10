// lib/core/utils/map_launcher_helper.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class MapLauncherHelper {
  static Future<void> openMapLocation({
    double? lat,
    double? lng,
    String? address,
    String? label,
  }) async {
    final hasCoords = lat != null && lng != null;
    final encAddr = (address == null || address.trim().isEmpty)
        ? null
        : Uri.encodeComponent(address.trim());
    final encLabel = (label == null || label.isEmpty)
        ? null
        : Uri.encodeComponent(label);

    if (!hasCoords && encAddr == null) {
      throw ArgumentError('Provide either latitude/longitude or an address.');
    }

    if (kIsWeb) {
      final web = hasCoords
          ? Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving')
          : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$encAddr&travelmode=driving');
      await launchUrl(web, mode: LaunchMode.externalApplication);
      return;
    }

    if (Platform.isIOS) {
      final googleScheme = hasCoords
          ? Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving${encLabel != null ? '&q=$encLabel' : ''}')
          : Uri.parse('comgooglemaps://?daddr=$encAddr&directionsmode=driving');

      final apple = hasCoords
          ? Uri.parse('maps://?daddr=$lat,$lng${encLabel != null ? '&q=$encLabel' : ''}&dirflg=d')
          : Uri.parse('maps://?daddr=$encAddr&dirflg=d');

      if (await canLaunchUrl(googleScheme)) {
        await launchUrl(googleScheme, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrl(apple, mode: LaunchMode.externalApplication);
      return;
    }

    if (Platform.isAndroid) {
      final googleNav = hasCoords
          ? Uri.parse('google.navigation:q=$lat,$lng&mode=d')
          : Uri.parse('google.navigation:q=$encAddr&mode=d');

      final geoQuery = hasCoords
          ? Uri.encodeComponent('$lat,$lng${label != null ? ' ($label)' : ''}')
          : Uri.encodeComponent(address!);
      final geo = Uri.parse('geo:0,0?q=$geoQuery');

      final web = hasCoords
          ? Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving')
          : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$encAddr&travelmode=driving');

      if (await canLaunchUrl(googleNav)) {
        await launchUrl(googleNav, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(geo)) {
        await launchUrl(geo, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrl(web, mode: LaunchMode.externalApplication);
      return;
    }

    // Fallback for other platforms
    final web = hasCoords
        ? Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving')
        : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$encAddr&travelmode=driving');
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  static void openMapFromLatLng(String? latLng, {String? label, String? address}) {
    if (latLng == null || latLng.trim().isEmpty) {
      if (address != null && address.trim().isNotEmpty) {
        openMapLocation(address: address, label: label);
      } else {
      }
      return;
    }

    final parts = latLng.split(',');
    if (parts.length != 2) {
      return;
    }

    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());

    if (lat == null || lng == null) {
      return;
    }

    openMapLocation(lat: lat, lng: lng, label: label);
  }
}
