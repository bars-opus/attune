// lib/features/dating/data/models/dating_introduction.dart

import 'package:flutter/material.dart';

class DatingIntroduction {
  final String id;
  final String displayName;
  final String? cityRegionCode;
  final String? relationshipIntention;
  final String? summary;
  final String
  displayBand; // 'limited_signal', 'some_shared_ground', 'promising_shared_ground'
  final Map<String, dynamic> explanationFeatures;
  final String
  state; // 'generated', 'presented', 'interested', 'passed', 'expired', 'invalidated'
  final DateTime expiresAt;
  final DateTime createdAt;
  final bool hasActed; // Whether the current user has acted

  const DatingIntroduction({
    required this.id,
    required this.displayName,
    required this.displayBand,
    required this.explanationFeatures,
    required this.state,
    required this.expiresAt,
    required this.createdAt,
    this.cityRegionCode,
    this.relationshipIntention,
    this.summary,
    this.hasActed = false,
  });

  factory DatingIntroduction.fromJson(Map<String, dynamic> json) {
    return DatingIntroduction(
      id: json['id'],
      displayName: json['display_name'] ?? 'Someone nearby',
      cityRegionCode: json['city_region_code'] as String?,
      relationshipIntention: json['relationship_intention'] as String?,
      summary: json['summary'] as String?,
      displayBand: json['display_band'],
      explanationFeatures: json['explanation_features'] ?? {},
      state: json['state'],
      expiresAt: DateTime.parse(json['expires_at']),
      createdAt: DateTime.parse(json['created_at']),
      hasActed: json['has_acted'] ?? false,
    );
  }

  String get bandLabel {
    switch (displayBand) {
      case 'limited_signal':
        return 'Limited signal';
      case 'some_shared_ground':
        return 'Some shared ground';
      case 'promising_shared_ground':
        return 'Promising shared ground';
      default:
        return displayBand;
    }
  }

  Color get bandColor {
    switch (displayBand) {
      case 'limited_signal':
        return Colors.grey;
      case 'some_shared_ground':
        return Colors.orange;
      case 'promising_shared_ground':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
