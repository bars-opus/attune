// test/features/couple_map/widget/world_outline_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/data/world_outline.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ByteData encode(List<List<(int, int)>> rings, {String magic = 'LND1'}) {
  final b = BytesBuilder();
  b.add(magic.codeUnits);
  final head = ByteData(4)..setUint32(0, rings.length, Endian.little);
  b.add(head.buffer.asUint8List());
  for (final r in rings) {
    final n = ByteData(4)..setUint32(0, r.length, Endian.little);
    b.add(n.buffer.asUint8List());
    for (final (x, y) in r) {
      final p =
          ByteData(4)
            ..setUint16(0, x, Endian.little)
            ..setUint16(2, y, Endian.little);
      b.add(p.buffer.asUint8List());
    }
  }
  return ByteData.sublistView(b.toBytes());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses rings into world units with their bounds', () {
    final o = WorldOutline.parse(
      encode([
        [(0, 0), (65535, 0), (65535, 32767)],
      ]),
    );
    expect(o.rings, hasLength(1));
    expect(o.rings.single[2], closeTo(1.0, 1e-6));
    expect(o.bounds.single.left, 0);
    expect(o.bounds.single.right, closeTo(1.0, 1e-6));
    expect(o.bounds.single.bottom, closeTo(0.5, 1e-4));
  });

  test('a wrong magic number is a FormatException', () {
    expect(
      () => WorldOutline.parse(encode(const [], magic: 'NOPE')),
      throwsFormatException,
    );
  });

  test('a truncated file is a FormatException', () {
    final full = encode([
      [(0, 0), (1, 1)],
    ]);
    expect(
      () => WorldOutline.parse(
        ByteData.sublistView(full, 0, full.lengthInBytes - 2),
      ),
      throwsFormatException,
    );
  });

  test('the bundled outline loads, is real, and stays under 400 KB', () async {
    final file = File(WorldOutline.asset);
    expect(file.lengthSync(), lessThanOrEqualTo(400 * 1024));
    final o = WorldOutline.parse(await rootBundle.load(WorldOutline.asset));
    expect(o.rings.length, greaterThan(1000));
    final points = o.rings.fold<int>(0, (n, r) => n + r.length ~/ 2);
    expect(points, greaterThan(40000));
  });

  test('the licence note names Natural Earth', () {
    expect(
      File('assets/geo/README.md').readAsStringSync(),
      contains('Natural Earth'),
    );
  });
}
