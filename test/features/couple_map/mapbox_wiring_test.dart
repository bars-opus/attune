// test/features/couple_map/mapbox_wiring_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src() =>
    File(
      'lib/features/couple_map/presentation/map/mapbox_couple_map_view.dart',
    ).readAsStringSync();

void main() {
  test('the location puck is turned off explicitly (spec §6.3)', () {
    expect(
      _src().contains('LocationComponentSettings(enabled: false)'),
      isTrue,
    );
  });

  test('the map canvas is excluded from semantics (spec §3.5)', () {
    expect(_src().contains('ExcludeSemantics('), isTrue);
  });

  test('the map takes its own gestures inside the swipeable tabs', () {
    expect(_src().contains('EagerGestureRecognizer'), isTrue);
  });

  test('presence is re-applied after a style change (Review Focus 2)', () {
    final s = _src();
    final loaded = s.substring(s.indexOf('Future<void> _styleLoaded()'));
    expect(loaded.contains('_last'), isTrue);
  });

  test('only a style failure counts as "no map" (tile errors are not)', () {
    expect(_src().contains('MapLoadErrorType.STYLE'), isTrue);
  });

  test(
    'the controller goes inert when its widget is disposed (checklist 2.10)',
    () {
      final s = _src();
      final dispose = s.substring(s.indexOf('void dispose()'));
      expect(dispose.contains('_map = null'), isTrue);
    },
  );

  test(
    'the Mapbox logo and attribution are lifted above the card (Mapbox terms)',
    () {
      final s = _src();
      expect(s.contains('LogoSettings('), isTrue);
      expect(s.contains('AttributionSettings('), isTrue);
    },
  );

  test(
    'areas are fills, never point circles; nothing is logged (checklist 4.4)',
    () {
      final s = _src();
      expect(s.contains('FillLayer('), isTrue);
      expect(s.contains('CircleLayer('), isFalse);
      expect(RegExp(r'\b(print|debugPrint)\(').hasMatch(s), isFalse);
    },
  );

  test('areas sit below labels and the avatar pins (slot: middle)', () {
    expect("slot: 'middle'".allMatches(_src()).length, greaterThanOrEqualTo(2));
  });

  test(
    'draws are serialised, and a superseded draw is skipped (Review Focus 1)',
    () {
      final s = _src();
      expect(s.contains('_queue = _queue.then('), isTrue);
      expect(s.contains('identical(p, _last)'), isTrue);
    },
  );

  test('the ornaments are lifted by what the tab says the card needs', () {
    expect(_src().contains('widget.ornamentBottom'), isTrue);
  });

  test(
    'stories are a clustered GeoJSON source, rebuilt (not layer-filtered) on change',
    () {
      final s = _src();
      expect(s.contains('cluster: true'), isTrue);
      expect(
        s
            .replaceAll(RegExp(r'\s'), '')
            .replaceAll(
              RegExp(r',(?=[\]}])'),
              '',
            ) // formatter's trailing commas
            .contains("clusterProperties:{'top':['max',['get','rank']]}"),
        isTrue,
      );
      expect(s.contains('_storySource'), isTrue);
    },
  );

  test('a tap resolves a pin or a whole cluster to story ids', () {
    final s = _src();
    expect(s.contains('queryRenderedFeatures('), isTrue);
    expect(s.contains('getGeoJsonClusterLeaves('), isTrue);
    expect(s.contains('widget.onStoriesTapped'), isTrue);
  });

  test('story pins never use a dot layer either', () {
    expect(_src().contains('CircleLayer('), isFalse);
  });

  test('a tap opens every story under the finger, not just the top one', () {
    final s = _src();
    final tap = s.substring(s.indexOf('Future<void> _onTap('));
    expect(tap.contains('firstOrNull'), isFalse);
    expect(tap.contains('for (final hit in hits'), isTrue);
  });

  test(
    'a story batch only uploads images that changed, and updates data in place',
    () {
      final s = _src();
      expect(s.contains('_imageAt'), isTrue);
      expect(s.contains('updateGeoJSON('), isTrue);
    },
  );
  test(
    'presence areas update in place; layers are rebuilt only when the colour changes',
    () {
      final s = _src();
      final draw = s.substring(
        s.indexOf('Future<void> _draw('),
        s.indexOf('Future<void> fitTo('),
      );
      expect(draw.contains('updateGeoJSON('), isTrue);
      expect(draw.contains('_areaColor'), isTrue);
    },
  );

  test('dark is tracked before onReady (Review Focus 4)', () {
    final s = _src();
    final update = s.substring(s.indexOf('void didUpdateWidget('));
    expect(update.contains('widget.dark'), isTrue);
  });
}
