enum LocationSource {
  current,  // From device GPS
  search,   // From manual search
}

class UserLocation {
  final String displayName;  // "New York, NY" or "Home"
  final double latitude;
  final double longitude;
  final LocationSource source;
  final DateTime timestamp;
  final String? currencyCode;     // 👈 Add this
  final String? currencySymbol;

  const UserLocation({
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.source,
    required this.timestamp,
    this.currencyCode,
    this.currencySymbol,
  });

  /// Create from JSON (for storage)
  factory UserLocation.fromJson(Map<String, dynamic> json) {
    return UserLocation(
      displayName: json['displayName'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      source: LocationSource.values.firstWhere(
        (e) => e.toString() == json['source'],
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
       currencyCode: json['currencyCode'] as String?,
      currencySymbol: json['currencySymbol'] as String?,
    );
  }

  /// Convert to JSON (for storage)
  Map<String, dynamic> toJson() {
    return {
      'displayName': displayName,
      'latitude': latitude,
      'longitude': longitude,
      'source': source.toString(),
      'timestamp': timestamp.toIso8601String(),
       'currencyCode': currencyCode,
    'currencySymbol': currencySymbol,
    };
  }

  /// Create a copy with updated fields
  UserLocation copyWith({
    String? displayName,
    double? latitude,
    double? longitude,
    LocationSource? source,
    DateTime? timestamp,
  }) {
    return UserLocation(
      displayName: displayName ?? this.displayName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      source: source ?? this.source,
      timestamp: timestamp ?? this.timestamp,

          currencySymbol: currencySymbol ?? this.currencySymbol,
             currencyCode: currencyCode ?? this.currencyCode,
    );
  }
}
