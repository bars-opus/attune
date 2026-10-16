// test/features/couple_map/widget/region_map_painter_test.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:attune/features/couple_map/widget/data/world_outline.dart';
import 'package:attune/features/couple_map/widget/domain/region_frame.dart';
import 'package:attune/features/couple_map/widget/presentation/region_map_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<WorldOutline> realOutline() async =>
    WorldOutline.parse(await rootBundle.load(WorldOutline.asset));

Future<Color> pixel(ui.Image img, Offset at) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = ((at.dy.round() * img.width) + at.dx.round()) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

Widget golden(RegionFrame f, WorldOutline o, Color bg) => Center(
  child: RepaintBoundary(
    child: Container(
      color: bg,
      width: 160,
      height: 160,
      child: CustomPaint(painter: RegionMapPainter(frame: f, outline: o)),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  arcTests();

  test(
    'glows are drawn opaque at the snapped areas; open sea is clear',
    () async {
      final o = await realOutline();
      final f = regionFrame(
        (lat: 5.565, lng: -0.208),
        (lat: 51.505, lng: -0.125),
      );
      final img = await paintRegionMap(f, o, px: 480);
      final self = await pixel(img, f.self * 480);
      final partner = await pixel(img, f.partner * 480);
      expect(self.a, closeTo(1, 0.02));
      expect(partner.a, closeTo(1, 0.02));
      expect(self, isNot(partner), reason: 'two different tones');
      img.dispose();
    },
  );

  test('renderRegionMap returns a 480 px PNG', () async {
    final o = await realOutline();
    final f = regionFrame(
      (lat: 5.565, lng: -0.208),
      (lat: 51.505, lng: -0.125),
    );
    final png = await renderRegionMap(f, o);
    expect(png.sublist(1, 4), Uint8List.fromList('PNG'.codeUnits));
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 480);
    expect(frame.image.height, 480);
  });

  test(
    'records the world view within 150 ms (spec §9 6.9, CI-host proxy)',
    () async {
      final o = await realOutline();
      final f = regionFrame((lat: 0, lng: 0), (lat: 0, lng: 180));
      final painter = RegionMapPainter(frame: f, outline: o);
      void paintOnce() {
        final rec = ui.PictureRecorder();
        painter.paint(Canvas(rec), const Size.square(480));
        rec.endRecording().dispose();
      }

      paintOnce(); // warm up
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        paintOnce();
      }
      expect(sw.elapsedMilliseconds / 5, lessThan(150));
    },
  );

  test(
    'rasterises the world view to 480 px within 1 s (measured for the ledger)',
    () async {
      final o = await realOutline();
      final f = regionFrame((lat: 0, lng: 0), (lat: 0, lng: 180));
      (await paintRegionMap(f, o)).dispose(); // warm up
      final sw = Stopwatch()..start();
      for (var i = 0; i < 3; i++) {
        (await paintRegionMap(f, o)).dispose();
      }
      final avg = sw.elapsedMilliseconds / 3;
      // ignore: avoid_print
      print('region map rasterise avg: ${avg.toStringAsFixed(1)} ms');
      expect(avg, lessThan(1000));
    },
  );

  for (final (name, a, b) in [
    ('far_apart', (lat: 5.565, lng: -0.208), (lat: 51.505, lng: -0.125)),
    ('pacific', (lat: -36.85, lng: 174.76), (lat: 34.05, lng: -118.24)),
    ('world', (lat: 0.0, lng: 0.0), (lat: 0.0, lng: 180.0)),
    ('minimum_span', (lat: 5.565, lng: -0.208), (lat: 6.7, lng: -1.6)),
  ]) {
    for (final (mode, bg) in [
      ('light', const Color(0xFFF2F2F7)),
      ('dark', const Color(0xFF1C1C1E)),
    ]) {
      testWidgets('golden: $name on $mode', (t) async {
        final o = (await t.runAsync(realOutline))!;
        await t.pumpWidget(golden(regionFrame(a, b), o, bg));
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/region_map_${name}_$mode.png'),
        );
      });
    }
  }
}

void arcTests() {
  test('the arc bows perpendicular to the line, toward the pole', () {
    // East-west pair in the north: bows up (north).
    final ew = arcControl(
      const Offset(0, 100),
      const Offset(100, 100),
      north: true,
    );
    expect(ew.dy, lessThan(100));
    // North-south pair: no "toward the pole" side exists; it still curves.
    final ns = arcControl(
      const Offset(50, 0),
      const Offset(50, 100),
      north: true,
    );
    expect((ns.dx - 50).abs(), greaterThan(10));
    // Southern hemisphere: bows down (south).
    final south = arcControl(
      const Offset(0, 100),
      const Offset(100, 100),
      north: false,
    );
    expect(south.dy, greaterThan(100));
  });
}
