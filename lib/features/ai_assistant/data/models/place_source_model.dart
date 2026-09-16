// lib/features/ai_assistant/data/models/place_source_model.dart

/// A Nearby search result, matching spec §5.2's `PlaceSource` field list
/// exactly:
///
/// ```typescript
/// {
///   provider_id: string;
///   name: string;
///   formatted_address: string | null;
///   category: string | null;
///   map_url: string | null; // server-built provider/place-id URL; no coordinates
/// }
/// ```
///
/// This never carries coordinates, distance, opening hours, price,
/// ratings, or accessibility claims — the server never sends them
/// (spec §5.2), so there is deliberately no field here for any of them.
class PlaceSourceModel {
  final String providerId;
  final String name;
  final String? formattedAddress;
  final String? category;
  final String? mapUrl;

  const PlaceSourceModel({
    required this.providerId,
    required this.name,
    this.formattedAddress,
    this.category,
    this.mapUrl,
  });

  /// Throws (via the `as` cast / `FormatException`) on a missing or
  /// mistyped required field rather than silently defaulting — a
  /// malformed source must never render as if the server had said
  /// something it didn't.
  factory PlaceSourceModel.fromJson(Map<String, dynamic> json) {
    final providerId = json['provider_id'];
    final name = json['name'];
    if (providerId is! String || providerId.isEmpty) {
      throw FormatException(
        'PlaceSourceModel.fromJson: missing/invalid provider_id',
      );
    }
    if (name is! String || name.isEmpty) {
      throw FormatException('PlaceSourceModel.fromJson: missing/invalid name');
    }
    return PlaceSourceModel(
      providerId: providerId,
      name: name,
      formattedAddress: json['formatted_address'] as String?,
      category: json['category'] as String?,
      mapUrl: json['map_url'] as String?,
    );
  }
}
