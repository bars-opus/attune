/// The couple map's own numbers (checklist 4.11). Presence timings live in
/// PresenceConfig, which mirrors SQL presence_config().
abstract final class CoupleMapConfig {
  /// A cell is ~1.11 km square and its centre is rounded to 0.001°, so its
  /// farthest corner is at most ~0.83 km away; 0.85 km covers the whole
  /// cell (spec §3.2: at least 1.6 km across).
  static const areaRadiusKm = 0.85;
  static const areaRingPoints = 48;

  /// Opacity of an area and avatar the server marks `fading` (4–8 h).
  static const fadingOpacity = 0.5;

  /// Avatar pin diameter, logical pixels.
  static const pinSize = 44.0;

  /// Rendered pin images kept in memory (checklist 2.12–2.15, 3.4).
  static const pinCacheEntries = 64;

  static const glassButtonSize = 44.0;
  static const fitPadding = 72.0;
  static const fitMaxZoom = 12.5;
  static const singleAreaZoom = 12.0;

  /// The tallest bottom card (two-line headline and details plus padding);
  /// the Mapbox logo and attribution sit above it.
  static const cardMaxHeight = 112.0;

  /// The device-only home-area warning radius (spec §3.3, "about 500 m").
  static const homeAreaRadiusM = 500.0;

  /// list_story_places' server cap (checklist 2.5).
  static const placesLimit = 500;

  /// Story thumbnail pin diameter, logical pixels.
  static const storyPinSize = 52.0;

  /// The story-place fix (only after the switch is on).
  static const placeFixTimeout = Duration(seconds: 20);

  /// The glass buttons' hit area (Android 48 dp guideline); the visual
  /// circle inside stays [glassButtonSize] (44 dp).
  static const glassTarget = 48.0;

  /// Between two hit areas (8 dp between the visuals).
  static const glassGap = 4.0;

  /// Between the top group and the zoom pair (16 dp between the visuals).
  static const glassGroupGap = 12.0;

  /// Where the right-hand column ends, for the compass: the top inset, the
  /// upper group (style, stories?, recentre, list), the group gap, the zoom
  /// pair, and a 16 dp margin.
  static double rightColumnBottom({required bool stories}) {
    final upper = stories ? 4 : 3;
    return 16 +
        upper * glassTarget +
        (upper - 1) * glassGap +
        glassGroupGap +
        2 * glassTarget +
        glassGap +
        16;
  }
}
