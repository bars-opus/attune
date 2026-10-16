// test/features/couple_map/support/fakes.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/couple_map/data/story_places_repository.dart';
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/data/story_place_resolver.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:attune/features/couple_map/presentation/map/couple_map_controller.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:flutter/material.dart';

class FakeCoupleMapController implements CoupleMapController {
  final styles = <(CoupleMapStyle, bool)>[];
  final presences = <(List<SceneArea>, Map<PresenceWho, Uint8List>, bool)>[];
  final fits = <(List<MapPoint>, bool)>[];
  final zooms = <(double, bool)>[];
  final stories = <(List<StoryScenePin>, Map<String, RawPin>)>[];

  List<SceneArea> get lastAreas => presences.last.$1;

  @override
  Future<void> setStyle(CoupleMapStyle style, {required bool dark}) async =>
      styles.add((style, dark));

  @override
  Future<void> setPresence(
    List<SceneArea> areas,
    Map<PresenceWho, Uint8List> avatars, {
    required Color areaColor,
    required bool together,
    required int pinSizePx,
  }) async => presences.add((areas, avatars, together));

  @override
  Future<void> fitTo(List<MapPoint> points, {required bool animate}) async =>
      fits.add((points, animate));

  @override
  Future<void> zoomBy(double delta, {required bool animate}) async =>
      zooms.add((delta, animate));

  @override
  Future<void> setStories(
    List<StoryScenePin> pins,
    Map<String, RawPin> images,
  ) async => stories.add((pins, images));
}

class FakeCoupleMapView {
  final controller = FakeCoupleMapController();
  int built = 0;
  CoupleMapStyle? builtStyle;
  bool? builtDark;
  double? builtOrnamentBottom;
  double? builtOrnamentTop;
  ValueChanged<List<String>>? _tap;

  /// Simulates a tap on story pins (one pin, or a whole cluster).
  void tapStories(List<String> ids) => _tap?.call(ids);
  VoidCallback? _fail;

  void failLoad() => _fail?.call();

  CoupleMapViewBuilder get builder => ({
    required CoupleMapStyle style,
    required bool dark,
    required ValueChanged<CoupleMapController> onReady,
    required VoidCallback onLoadError,
    required double ornamentBottom,
    required double ornamentTop,
    required ValueChanged<List<String>> onStoriesTapped,
  }) {
    built++;
    builtOrnamentTop = ornamentTop;
    _tap = onStoriesTapped;
    builtStyle = style;
    builtDark = dark;
    builtOrnamentBottom = ornamentBottom;
    _fail = onLoadError;
    return _FakeMap(onReady: () => onReady(controller));
  };
}

class _FakeMap extends StatefulWidget {
  const _FakeMap({required this.onReady});
  final VoidCallback onReady;
  @override
  State<_FakeMap> createState() => _FakeMapState();
}

class _FakeMapState extends State<_FakeMap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady());
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFFDDE5EC), key: ValueKey('fake-map'));
}

class FakePinImageRenderer extends PinImageRenderer {
  final rendered = <PinSpec>[];
  final _kept = <PinSpec>{};

  /// Initials whose render waits for this to complete (race tests).
  final hold = <String, Completer<void>>{};

  @override
  Future<Uint8List> render(PinSpec spec) async {
    rendered.add(spec);
    await hold[spec.initials]?.future;
    _kept.add(spec);
    return Uint8List.fromList(spec.initials.codeUnits);
  }

  final rawRendered = <PinSpec>[];

  @override
  Future<RawPin>? peekRaw(PinSpec spec) =>
      _kept.contains(spec)
          ? Future.value(RawPin(rgba: Uint8List(4), width: 1, height: 1))
          : null;

  @override
  Future<RawPin> renderRaw(PinSpec spec) async {
    rawRendered.add(spec);
    _kept.add(spec);
    return RawPin(rgba: Uint8List(4), width: 1, height: 1);
  }

  @override
  int get length => _kept.length;

  @override
  void clear() => _kept.clear();
}

class FakeStoryPlacesGateway implements StoryPlacesGateway {
  FakeStoryPlacesGateway([
    Map<String, dynamic Function(Map<String, dynamic>)>? handlers,
  ]) : handlers = handlers ?? {};
  final Map<String, dynamic Function(Map<String, dynamic>)> handlers;
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) async {
    calls.add((fn, params ?? const {}));
    final h = handlers[fn];
    return h == null ? null : h(params ?? const {});
  }
}

class MemoryCoupleMapLocalStore implements CoupleMapLocalStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class FakeStoryPlaceResolver implements StoryPlaceResolver {
  FakeStoryPlaceResolver([this.next]);
  StoryPlaceDraft? next;
  StoryPlaceProblem? problem;
  bool approximate = false;
  int calls = 0;
  final asks = <bool>[];
  Completer<void>? hold;
  @override
  Future<StoryPlaceLookup> resolve({required bool ask}) async {
    calls++;
    asks.add(ask);
    await hold?.future;
    final p = problem;
    if (p != null) return StoryPlaceLookup.failed(p);
    final d = next;
    return d == null
        ? const StoryPlaceLookup.failed(StoryPlaceProblem.notFound)
        : StoryPlaceLookup.found(d, approximate: approximate);
  }
}

Map<String, Object?> storyPlaceRow(
  String id, {
  String author = 'kofi',
  double lat = 5.556,
  double lng = -0.197,
  String created = '2026-10-16T09:00:00Z',
}) => {
  'story_item_id': id,
  'relationship_id': 'r1',
  'author_id': author,
  'lat': lat,
  'lng': lng,
  'label': 'Near Osu, Accra',
  'placed_at': created,
  'client_story_id': 'c-$id',
  'media_type': 'image',
  'media_key': 'k/$id.jpg',
  'thumbnail_key': 't/$id.jpg',
  'media_width': 1080,
  'media_height': 1920,
  'duration_ms': null,
  'occurred_on': created.substring(0, 10),
  'created_at': created,
  'expires_at': '2026-10-17T09:00:00Z',
};
