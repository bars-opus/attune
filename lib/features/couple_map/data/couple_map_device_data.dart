import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Clears what the couple map keeps on this device (quick exit, spec §3.6):
/// the Mapbox tile and style cache (it holds the partner's area), the
/// rendered pins, and the device-only settings — the last pin choice, the
/// home area and the stories hint. Server presence is deliberately
/// untouched: a sudden disappearance would itself be a signal.
///
/// Everything runs at once: quick exit leaves the app 300 ms after starting
/// this, so the store deletes must not hold up the tile-cache clear.
/// The home-screen widget is cleared first (widget spec §6.4).
Future<void> clearCoupleMapDeviceData({
  Future<void> Function()? clearMapCache,
  PinImageRenderer? pins,
  CoupleMapLocalStore? store,
}) async {
  final widget = CoupleWidgetSync.clear();
  (pins ?? sharedPinImageRenderer).clear();
  final s = store ?? SecureCoupleMapLocalStore();
  await Future.wait([
    widget,
    for (final key in CoupleMapLocalKeys.all) s.delete(key),
    Future(
      () => (clearMapCache ?? MapboxMapsOptions.clearData)(),
    ).catchError((Object _) {}),
  ]);
}
