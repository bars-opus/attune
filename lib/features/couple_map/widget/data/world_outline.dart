// lib/features/couple_map/widget/data/world_outline.dart
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bundled land outline (Natural Earth 1:50m, public domain), already
/// in Web Mercator world units, so a render does no trigonometry.
class WorldOutline {
  WorldOutline._(this.rings, this.bounds);

  static const asset = 'assets/geo/land_50m_merc.bin';

  /// Bumped when the asset changes (part of the render cache key).
  static const version = 1;

  /// Interleaved x,y in world units (0..1).
  final List<Float32List> rings;
  final List<Rect> bounds;

  static WorldOutline parse(ByteData data) {
    try {
      if (data.lengthInBytes < 8 ||
          String.fromCharCodes([
                for (var i = 0; i < 4; i++) data.getUint8(i),
              ]) !=
              'LND1') {
        throw const FormatException('not a land outline');
      }
      var o = 4;
      final count = data.getUint32(o, Endian.little);
      o += 4;
      final rings = <Float32List>[];
      final bounds = <Rect>[];
      for (var r = 0; r < count; r++) {
        final n = data.getUint32(o, Endian.little);
        o += 4;
        final pts = Float32List(n * 2);
        var l = 1.0, t = 1.0, rt = 0.0, b = 0.0;
        for (var i = 0; i < n; i++) {
          final x = data.getUint16(o, Endian.little) / 65535;
          final y = data.getUint16(o + 2, Endian.little) / 65535;
          o += 4;
          pts[i * 2] = x;
          pts[i * 2 + 1] = y;
          if (x < l) l = x;
          if (x > rt) rt = x;
          if (y < t) t = y;
          if (y > b) b = y;
        }
        rings.add(pts);
        bounds.add(Rect.fromLTRB(l, t, rt, b));
      }
      return WorldOutline._(rings, bounds);
    } on RangeError {
      throw const FormatException('truncated land outline');
    }
  }
}

final worldOutlineProvider = FutureProvider<WorldOutline>(
  (ref) async => WorldOutline.parse(await rootBundle.load(WorldOutline.asset)),
);
