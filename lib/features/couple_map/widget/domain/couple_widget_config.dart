// lib/features/couple_map/widget/domain/couple_widget_config.dart
/// The home-screen widget's tunables (spec §9, 4.11).
abstract final class CoupleWidgetConfig {
  static const payloadVersion = 1;

  /// How long a written distance stays on the widget (spec §4.2).
  static const validFor = Duration(hours: 3);

  /// The region map appears from this distance (spec §3.3).
  static const mapMinKm = 100.0;

  /// Draw-only coarsening of each area (~55 km).
  static const gridDegrees = 0.5;

  /// The map never shows less than this across.
  static const minSpanKm = 600.0;

  /// Both glows sit inside this central fraction of the square.
  static const fitFraction = 0.5;

  /// At most one widget read per this long.
  static const readDebounce = Duration(minutes: 5);

  static const imagePx = 480;
  static const renderBudget = Duration(seconds: 2);

  /// Glow radius as a fraction of the image side (20 pt on a 160 pt pane).
  static const glowRadiusFraction = 0.125;
}
