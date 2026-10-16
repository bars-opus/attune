import 'dart:async';

import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:attune/features/couple_map/presentation/map/couple_map_controller.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

Widget mapboxCoupleMapViewBuilder({
  required CoupleMapStyle style,
  required bool dark,
  required ValueChanged<CoupleMapController> onReady,
  required VoidCallback onLoadError,
  required double ornamentBottom,
  required double ornamentTop,
  required ValueChanged<List<String>> onStoriesTapped,
}) => MapboxCoupleMapView(
  style: style,
  dark: dark,
  onReady: onReady,
  onLoadError: onLoadError,
  ornamentBottom: ornamentBottom,
  ornamentTop: ornamentTop,
  onStoriesTapped: onStoriesTapped,
);

class MapboxCoupleMapView extends StatefulWidget {
  const MapboxCoupleMapView({
    super.key,
    required this.style,
    required this.dark,
    required this.onReady,
    required this.onLoadError,
    required this.ornamentBottom,
    required this.ornamentTop,
    required this.onStoriesTapped,
  });
  final CoupleMapStyle style;
  final bool dark;
  final ValueChanged<CoupleMapController> onReady;
  final VoidCallback onLoadError;

  /// How far up the Mapbox logo and attribution sit: above the tallest
  /// bottom card, so they stay visible (Mapbox terms).
  final double ornamentBottom;

  /// How far down the compass sits: under the tab's right-hand column,
  /// whose height changes when the Stories button shows.
  final double ornamentTop;

  /// Story ids under a tapped pin, or every story in a tapped cluster.
  final ValueChanged<List<String>> onStoriesTapped;

  @override
  State<MapboxCoupleMapView> createState() => _MapboxCoupleMapViewState();
}

typedef _Presence =
    ({
      List<SceneArea> areas,
      Map<PresenceWho, Uint8List> avatars,
      Color areaColor,
      bool together,
      int pinSizePx,
    });

class _MapboxCoupleMapViewState extends State<MapboxCoupleMapView>
    implements CoupleMapController {
  static const _source = 'couple-presence-areas';
  static const _fill = 'couple-presence-fill';
  static const _outline = 'couple-presence-outline';
  static const _storySource = 'couple-stories';
  static const _storyPins = 'couple-stories-pins';
  static const _storyClusters = 'couple-stories-clusters';

  MapboxMap? _map;
  PointAnnotationManager? _pins;
  late CoupleMapStyle _style = widget.style;
  late bool _dark = widget.dark;

  /// The last presence, re-applied after a style change: a new style drops
  /// every runtime source and layer.
  _Presence? _last;

  /// Sources and layers can be added only once the style has loaded;
  /// onMapCreated usually fires first.
  bool _styleReady = false;

  /// The last story set, re-applied after a style change.
  ({List<StoryScenePin> pins, Map<String, RawPin> images})? _lastStories;

  /// The area colour the layers were built with (rebuilt only on change).
  int? _areaColor;

  /// Rank-keyed style images currently added (a new style drops them).
  int _storyImageCount = 0;

  /// Which story each rank's image currently shows, and the source data
  /// last set, so a batch uploads only what changed.
  final _imageAt = <int, String>{};
  String? _storyData;

  /// Device pixel ratio for story images (they're storyPinSize × dpr).
  double _storyScale = 1;

  /// Draws run one at a time: interleaved awaits could otherwise leave two
  /// pin sets, or drop the newer areas.
  Future<void> _queue = Future.value();

  @override
  void dispose() {
    // The tab may still hold this controller: make every call a no-op.
    _map = null;
    _pins = null;
    super.dispose();
  }

  static String _uri(CoupleMapStyle s) => switch (s) {
    CoupleMapStyle.standard => MapboxStyles.STANDARD,
    CoupleMapStyle.satellite => MapboxStyles.STANDARD_SATELLITE,
  };

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: MapWidget(
        key: const ValueKey('couple-map'),
        styleUri: _uri(_style),
        // Initial camera only. Not `viewport`: a viewport state passed on every
        // build could pull the camera back over our fitTo/zoom calls.
        // ignore: deprecated_member_use
        cameraOptions: CameraOptions(zoom: 1.5),
        // The map sits in a swipeable TabBarView: it takes its own pans.
        gestureRecognizers: {
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        onMapCreated: _created,
        onStyleLoadedListener: (_) => _styleLoaded(),
        // Only a style failure means "no map". A tile, sprite or glyph
        // error on a flaky connection must not swap the map for the list.
        onMapLoadErrorListener: (e) {
          if (e.type == MapLoadErrorType.STYLE) widget.onLoadError();
        },
      ),
    );
  }

  Future<void> _created(MapboxMap map) async {
    _map = map;
    // Never the "you are here" puck: it would draw a raw position (§6.3).
    await map.location.updateSettings(
      LocationComponentSettings(enabled: false),
    );
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    // Below the tab's right-hand column (the tab measures it). Shows only
    // when rotated.
    await map.compass.updateSettings(
      CompassSettings(
        position: OrnamentPosition.TOP_RIGHT,
        marginTop: widget.ornamentTop,
        marginRight: 16,
      ),
    );
    // Mapbox's terms require the logo and attribution to stay visible: lift
    // them above the distance card.
    await map.logo.updateSettings(
      LogoSettings(
        position: OrnamentPosition.BOTTOM_LEFT,
        marginBottom: widget.ornamentBottom,
        marginLeft: 16,
      ),
    );
    await map.attribution.updateSettings(
      AttributionSettings(
        position: OrnamentPosition.BOTTOM_RIGHT,
        marginBottom: widget.ornamentBottom,
        marginRight: 16,
      ),
    );
    // Flat: areas stay round and readable.
    await map.gestures.updateSettings(GesturesSettings(pitchEnabled: false));
    _pins = await map.annotations.createPointAnnotationManager();
    // Story pin and cluster taps (the non-deprecated tap route).
    map.addInteraction(TapInteraction.onMap((ctx) => unawaited(_onTap(ctx))));
    if (mounted) widget.onReady(this);
  }

  Future<void> _styleLoaded() async {
    final map = _map;
    if (map == null) return;
    _styleReady = true;
    if (_style == CoupleMapStyle.standard) {
      await map.style.setStyleImportConfigProperty(
        'basemap',
        'lightPreset',
        _dark ? 'night' : 'day',
      );
    }
    // A new style dropped every image and source: forget them first.
    _areaColor = null;
    _storyImageCount = 0;
    _imageAt.clear();
    _storyData = null;
    final last = _last;
    if (last != null) await _apply(last);
    final stories = _lastStories;
    if (stories != null) await _applyStories(stories);
  }

  @override
  void didUpdateWidget(MapboxCoupleMapView old) {
    super.didUpdateWidget(old);
    // The Stories button showing or hiding moves the column's end.
    if (old.ornamentTop != widget.ornamentTop) {
      _map?.compass.updateSettings(
        CompassSettings(marginTop: widget.ornamentTop),
      );
    }
    // A theme flip before onReady: the first style load must use it. (The
    // tab's own post-frame setStyle may repeat this; harmless.)
    if (old.dark != widget.dark) {
      _dark = widget.dark;
      final map = _map;
      if (map != null && _styleReady && _style == CoupleMapStyle.standard) {
        unawaited(
          map.style.setStyleImportConfigProperty(
            'basemap',
            'lightPreset',
            _dark ? 'night' : 'day',
          ),
        );
      }
    }
  }

  @override
  Future<void> setStyle(CoupleMapStyle style, {required bool dark}) async {
    final map = _map;
    final changed = style != _style;
    _style = style;
    _dark = dark;
    if (map == null) return;
    if (changed) {
      _styleReady = false;
      await map.loadStyleURI(_uri(style)); // _styleLoaded re-applies presence
    } else if (style == CoupleMapStyle.standard) {
      await map.style.setStyleImportConfigProperty(
        'basemap',
        'lightPreset',
        dark ? 'night' : 'day',
      );
    }
  }

  @override
  Future<void> setPresence(
    List<SceneArea> areas,
    Map<PresenceWho, Uint8List> avatars, {
    required Color areaColor,
    required bool together,
    required int pinSizePx,
  }) async {
    final p = (
      areas: areas,
      avatars: avatars,
      areaColor: areaColor,
      together: together,
      pinSizePx: pinSizePx,
    );
    _last = p;
    await _apply(p);
  }

  Future<void> _apply(_Presence p) {
    _queue = _queue.then((_) async {
      // A newer presence has arrived since this draw was queued: skip it.
      if (!identical(p, _last)) return;
      final map = _map;
      final pins = _pins;
      if (map == null || pins == null || !_styleReady) return;
      try {
        await _draw(map, pins, p);
      } catch (_) {
        // A style swapped mid-draw: _styleLoaded re-applies _last. No log
        // (it would carry nothing useful and must never carry a place).
      }
    });
    return _queue;
  }

  Future<void> _draw(
    MapboxMap map,
    PointAnnotationManager pins,
    _Presence p,
  ) async {
    final style = map.style;
    final data = areasGeoJson(p.areas, together: p.together);
    final colour = p.areaColor.toARGB32();
    if (_areaColor == colour && await style.styleSourceExists(_source)) {
      // Same look, new areas: update the data in place (no flicker).
      final source = await style.getSource(_source);
      if (source is GeoJsonSource) await source.updateGeoJSON(data);
    } else {
      await _rebuildAreas(style, data, p.areaColor);
      _areaColor = colour;
    }
    await pins.deleteAll();
    // iconOffset is in image pixels (the PNG is pinSize × dpr).
    final offset = p.pinSizePx * 0.6;
    await pins.createMulti([
      for (final a in p.areas)
        if (p.avatars[a.who] case final image?)
          PointAnnotationOptions(
            geometry: Point(coordinates: Position(a.centre.lng, a.centre.lat)),
            image: image,
            iconOpacity: a.opacity,
            iconOffset:
                p.together
                    ? [a.who == PresenceWho.self ? -offset : offset, 0]
                    : [0, 0],
          ),
    ]);
  }

  /// The area source and its two layers, from scratch (first draw, a new
  /// style, or a theme colour change).
  Future<void> _rebuildAreas(
    StyleManager style,
    String data,
    Color colour,
  ) async {
    for (final layer in [_outline, _fill]) {
      if (await style.styleLayerExists(layer)) {
        await style.removeStyleLayer(layer);
      }
    }
    if (await style.styleSourceExists(_source)) {
      await style.removeStyleSource(_source);
    }
    await style.addSource(GeoJsonSource(id: _source, data: data));
    await style.addLayer(
      FillLayer(
        id: _fill,
        sourceId: _source,
        // Below labels and below the (unslotted) avatar annotations.
        slot: 'middle',
        fillColor: colour.toARGB32(),
        fillOpacityExpression: [
          '*',
          0.22,
          ['get', 'opacity'],
        ],
      ),
    );
    await style.addLayer(
      LineLayer(
        id: _outline,
        sourceId: _source,
        slot: 'middle',
        lineColor: colour.toARGB32(),
        lineWidth: 1.5,
        lineOpacityExpression: [
          '*',
          0.6,
          ['get', 'opacity'],
        ],
      ),
    );
  }

  @override
  Future<void> fitTo(List<MapPoint> points, {required bool animate}) async {
    final map = _map;
    if (map == null || points.isEmpty) return;
    const pad = CoupleMapConfig.fitPadding;
    final camera =
        points.length == 1
            ? CameraOptions(
              center: Point(
                coordinates: Position(points.first.lng, points.first.lat),
              ),
              zoom: CoupleMapConfig.singleAreaZoom,
            )
            : await map.cameraForCoordinatesPadding(
              [
                for (final p in points)
                  Point(coordinates: Position(p.lng, p.lat)),
              ],
              CameraOptions(),
              MbxEdgeInsets(top: pad, left: pad, bottom: pad * 2, right: pad),
              CoupleMapConfig.fitMaxZoom,
              null,
            );
    animate
        ? await map.flyTo(camera, MapAnimationOptions(duration: 800))
        : await map.setCamera(camera);
  }

  @override
  Future<void> zoomBy(double delta, {required bool animate}) async {
    final map = _map;
    if (map == null) return;
    final state = await map.getCameraState();
    final camera = CameraOptions(zoom: state.zoom + delta);
    animate
        ? await map.easeTo(camera, MapAnimationOptions(duration: 250))
        : await map.setCamera(camera);
  }

  @override
  Future<void> setStories(
    List<StoryScenePin> pins,
    Map<String, RawPin> images,
  ) {
    // Read now, while the context is valid; the draw runs after awaits.
    _storyScale = MediaQuery.devicePixelRatioOf(context);
    final s = (pins: pins, images: images);
    _lastStories = s;
    return _applyStories(s);
  }

  /// Serialised with presence draws; a superseded set is skipped. The
  /// source is rebuilt from the filtered set, so cluster counts are right.
  Future<void> _applyStories(
    ({List<StoryScenePin> pins, Map<String, RawPin> images}) s,
  ) {
    _queue = _queue.then((_) async {
      if (!identical(s, _lastStories)) return;
      final map = _map;
      if (map == null || !_styleReady) return;
      try {
        final style = map.style;
        // Rank-keyed images: drop the ones a smaller set no longer uses.
        for (var i = s.pins.length; i < _storyImageCount; i++) {
          if (await style.hasStyleImage('story-$i')) {
            await style.removeStyleImage('story-$i');
          }
          _imageAt.remove(i);
        }
        _storyImageCount = s.pins.length;
        if (s.pins.isEmpty) {
          for (final layer in [_storyClusters, _storyPins]) {
            if (await style.styleLayerExists(layer)) {
              await style.removeStyleLayer(layer);
            }
          }
          if (await style.styleSourceExists(_storySource)) {
            await style.removeStyleSource(_storySource);
          }
          return;
        }
        // Upload only images whose rank now shows a different story (a
        // thumbnail batch adds a few; a refresh of the same set adds none).
        for (final pin in s.pins) {
          final img = s.images[pin.storyItemId];
          if (img == null || _imageAt[pin.rank] == pin.storyItemId) continue;
          _imageAt[pin.rank] = pin.storyItemId;
          await style.addStyleImage(
            'story-${pin.rank}',
            _storyScale,
            MbxImage(width: img.width, height: img.height, data: img.rgba),
            false,
            [],
            [],
            null,
          );
        }
        final data = storiesGeoJson(s.pins);
        if (await style.styleSourceExists(_storySource)) {
          // Same layers, new points: update the data in place (no flicker).
          if (data != _storyData) {
            final source = await style.getSource(_storySource);
            if (source is GeoJsonSource) await source.updateGeoJSON(data);
            _storyData = data;
          }
          return;
        }
        _storyData = data;
        await style.addSource(
          GeoJsonSource(
            id: _storySource,
            data: data,
            cluster: true,
            clusterRadius: 50,
            clusterMaxZoom: 14,
            clusterProperties: {
              'top': [
                'max',
                ['get', 'rank'],
              ],
            },
          ),
        );
        await style.addLayer(
          SymbolLayer(
            id: _storyPins,
            sourceId: _storySource,
            // Above labels: story pins are what this layer is for.
            slot: 'top',
            filter: [
              '!',
              ['has', 'point_count'],
            ],
            iconImageExpression: [
              'concat',
              'story-',
              [
                'to-string',
                ['get', 'rank'],
              ],
            ],
            iconAllowOverlap: true,
          ),
        );
        await style.addLayer(
          SymbolLayer(
            id: _storyClusters,
            sourceId: _storySource,
            slot: 'top',
            filter: ['has', 'point_count'],
            // The newest story's thumbnail, a little larger, with a count.
            iconImageExpression: [
              'concat',
              'story-',
              [
                'to-string',
                ['get', 'top'],
              ],
            ],
            iconSize: 1.15,
            iconAllowOverlap: true,
            // On the rim, with a heavy halo, so it reads over any photo.
            textFieldExpression: ['get', 'point_count_abbreviated'],
            textSize: 13,
            textOffset: [1.9, -1.9],
            textColor: 0xFFFFFFFF,
            textHaloColor: 0xE6000000,
            textHaloWidth: 2,
            textAllowOverlap: true,
          ),
        );
      } catch (_) {
        // A style swapped mid-draw: _styleLoaded re-applies. No log.
      }
    });
    return _queue;
  }

  Future<void> _onTap(MapContentGestureContext ctx) async {
    final map = _map;
    if (map == null) return;
    try {
      final hits = await map.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(ctx.touchPosition),
        RenderedQueryOptions(layerIds: [_storyPins, _storyClusters]),
      );
      // Every story under the finger: past the cluster zoom, two stories
      // from the same spot overlap, and both must be reachable.
      final ids = <String>{};
      for (final hit in hits.whereType<QueriedRenderedFeature>()) {
        final feature = hit.queriedFeature.feature;
        final props = Map<String?, Object?>.from(
          feature['properties'] as Map? ?? const {},
        );
        if (props.containsKey('point_count')) {
          final leaves = await map.getGeoJsonClusterLeaves(
            _storySource,
            feature,
            500,
            0,
          );
          for (final f
              in leaves.featureCollection ?? const <Map<String?, Object?>?>[]) {
            if ((f?['properties'] as Map?)?['id'] case final String id) {
              ids.add(id);
            }
          }
        } else if (props['id'] case final String id) {
          ids.add(id);
        }
      }
      if (ids.isNotEmpty) widget.onStoriesTapped(ids.toList());
    } catch (_) {}
  }
}
