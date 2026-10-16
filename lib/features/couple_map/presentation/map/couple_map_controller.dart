import 'dart:typed_data';

import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:flutter/widgets.dart';

enum CoupleMapStyle { standard, satellite }

/// The seam between the tab and the map engine (spec §6.2). Mapbox in the
/// app; a recording fake in tests.
abstract class CoupleMapController {
  Future<void> setStyle(CoupleMapStyle style, {required bool dark});

  Future<void> setPresence(
    List<SceneArea> areas,
    Map<PresenceWho, Uint8List> avatars, {
    required Color areaColor,
    required bool together,
    required int pinSizePx,
  });

  Future<void> fitTo(List<MapPoint> points, {required bool animate});

  Future<void> zoomBy(double delta, {required bool animate});

  /// Story pins (couple map Phase 2): [images] keyed by story id; a pin
  /// without an image yet is skipped until one arrives.
  Future<void> setStories(List<StoryScenePin> pins, Map<String, RawPin> images);
}

typedef CoupleMapViewBuilder =
    Widget Function({
      required CoupleMapStyle style,
      required bool dark,
      required ValueChanged<CoupleMapController> onReady,
      required VoidCallback onLoadError,
      required double ornamentBottom,
      required double ornamentTop,
      required ValueChanged<List<String>> onStoriesTapped,
    });
