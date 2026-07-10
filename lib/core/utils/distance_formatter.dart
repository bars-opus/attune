// lib/core/utils/distance_formatter.dart

import 'dart:ui';

import 'package:flutter/material.dart';

class DistanceFormatter {
  static String format(double distanceKm) {
    // If distance is extremely small (less than 0.001 km = 1 meter)
    if (distanceKm < 0.001) {
      return '${(distanceKm * 1000).toStringAsFixed(0)} mm';
    }
    // Less than 1 km - show in meters
    if (distanceKm < 1.0) {
      final meters = (distanceKm * 1000).round();
      return '$meters m';
    }
    // Less than 10 km - show with 1 decimal
    if (distanceKm < 10) {
      return '${distanceKm.toStringAsFixed(1)} km';
    }
    // 10-50 km - show as integer
    if (distanceKm < 50) {
      return '${distanceKm.round()} km';
    }
    // Very far
    return 'Very far';
  }

  static Color getDistanceColor(double distanceKm) {
    if (distanceKm < 2.0) return Colors.green;
    if (distanceKm < 5.0) return Colors.orange;
    if (distanceKm < 10.0) return Colors.amber;
    return Colors.red; // Very far
  }

  static IconData getDistanceIcon(double distanceKm) {
    if (distanceKm < 2.0) return Icons.near_me;
    if (distanceKm < 5.0) return Icons.directions_walk;
    if (distanceKm < 10.0) return Icons.directions_bike;
    return Icons.directions_car;
  }
}
