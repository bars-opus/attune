// tool/build_land_outline.dart
// Builds assets/geo/land_50m_merc.bin from Natural Earth's 1:50m land
// GeoJSON (public domain). Usage:
//   dart run tool/build_land_outline.dart <ne_50m_land.geojson> assets/geo/land_50m_merc.bin
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _maxLat = 85.0;

int _q(double unit) => (unit.clamp(0.0, 1.0) * 65535).round();

(int, int) _project(num lng, num lat) {
  final la = lat.toDouble().clamp(-_maxLat, _maxLat) * pi / 180;
  final x = (lng.toDouble() + 180) / 360;
  final y = (1 - log(tan(pi / 4 + la / 2)) / pi) / 2;
  return (_q(x), _q(y));
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: build_land_outline <in.geojson> <out.bin>');
    exit(64);
  }
  final geo = jsonDecode(File(args[0]).readAsStringSync()) as Map;
  final rings = <List<(int, int)>>[];
  for (final f in geo['features'] as List) {
    final g = (f as Map)['geometry'] as Map;
    final polys =
        g['type'] == 'Polygon'
            ? [g['coordinates'] as List]
            : (g['coordinates'] as List).cast<List>();
    for (final poly in polys) {
      for (final ring in poly) {
        final out = <(int, int)>[];
        for (final c in ring as List) {
          final p = _project((c as List)[0] as num, c[1] as num);
          if (out.isEmpty || out.last != p) out.add(p);
        }
        if (out.length >= 3) rings.add(out);
      }
    }
  }
  final b = BytesBuilder()..add('LND1'.codeUnits);
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  u32(rings.length);
  for (final r in rings) {
    u32(r.length);
    for (final (x, y) in r) {
      b.add(
        (ByteData(4)
              ..setUint16(0, x, Endian.little)
              ..setUint16(2, y, Endian.little))
            .buffer
            .asUint8List(),
      );
    }
  }
  File(args[1])
    ..createSync(recursive: true)
    ..writeAsBytesSync(b.toBytes());
  stdout.writeln('${rings.length} rings → ${args[1]}');
}
