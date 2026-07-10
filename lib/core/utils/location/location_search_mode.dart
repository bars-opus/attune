enum LocationSearchMode {
  /// Search for cities / localities — used for the client's personal discovery location.
  /// Mapbox types: place, locality, district
  city,

  /// Search for full street addresses — used when a shop or freelancer sets their location.
  /// Mapbox types: address
  address,
}
