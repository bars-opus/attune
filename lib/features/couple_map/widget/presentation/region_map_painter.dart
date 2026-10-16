// lib/features/couple_map/widget/presentation/region_map_painter.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:attune/app/theme/app_colors.dart';
import 'package:attune/features/couple_map/widget/data/world_outline.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_config.dart';
import 'package:attune/features/couple_map/widget/domain/region_frame.dart';
import 'package:flutter/material.dart';

/// Mid-grey at ~22 %: reads on light and dark widget backgrounds alike, so
/// one transparent image serves both (spec §3.3).
const regionLandColor = Color(0x38808080);

/// Mine is the app's green; theirs the warm accent.
const regionSelfColor = LightColors.primary;
const regionPartnerColor = LightColors.against;

/// Land, two fixed-size glows and a dashed arc. No text, labels or dots.
class RegionMapPainter extends CustomPainter {
  RegionMapPainter({required this.frame, required this.outline});

  final RegionFrame frame;
  final WorldOutline outline;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / frame.side;
    final view = Rect.fromLTWH(frame.left, frame.top, frame.side, frame.side);
    final land = Paint()..color = regionLandColor;
    // Copies one world either side fill the frame across the antimeridian.
    for (final shift in const [-1.0, 0.0, 1.0]) {
      final path = Path();
      for (var r = 0; r < outline.rings.length; r++) {
        final b = outline.bounds[r].shift(Offset(shift, 0));
        if (!b.overlaps(view)) continue;
        if (b.width * scale < 1 && b.height * scale < 1) continue;
        final pts = outline.rings[r];
        path.moveTo(
          (pts[0] + shift - frame.left) * scale,
          (pts[1] - frame.top) * scale,
        );
        for (var i = 2; i < pts.length; i += 2) {
          path.lineTo(
            (pts[i] + shift - frame.left) * scale,
            (pts[i + 1] - frame.top) * scale,
          );
        }
        path.close();
      }
      canvas.drawPath(path, land);
    }

    final a = Offset(frame.self.dx * size.width, frame.self.dy * size.height);
    final b = Offset(
      frame.partner.dx * size.width,
      frame.partner.dy * size.height,
    );
    final glow = size.width * CoupleWidgetConfig.glowRadiusFraction;
    if ((b - a).distance > glow) {
      final control = arcControl(a, b, north: frame.north);
      final arc =
          Path()
            ..moveTo(a.dx, a.dy)
            ..quadraticBezierTo(control.dx, control.dy, b.dx, b.dy);
      final dash =
          Paint()
            ..color = regionSelfColor.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = size.width / 120;
      final on = size.width / 48;
      final off = size.width / 64;
      for (final m in arc.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += on + off) {
          canvas.drawPath(m.extractPath(d, d + on), dash);
        }
      }
    }
    _glow(canvas, a, glow, regionSelfColor);
    _glow(canvas, b, glow, regionPartnerColor);
  }

  void _glow(Canvas canvas, Offset c, double r, Color color) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color,
            color,
            color.withValues(alpha: 0.35),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.28, 0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(RegionMapPainter old) =>
      old.frame.cacheKey != frame.cacheKey || old.outline != outline;
}

/// The arc's bezier control point: a quarter of the distance off the
/// midpoint, perpendicular to the line, on the side toward the nearer pole.
/// A north-south pair has no such side; it bows east.
Offset arcControl(Offset a, Offset b, {required bool north}) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return a;
  var perp = Offset(-d.dy, d.dx) / len;
  if (perp.dy.abs() < 1e-6) {
    if (perp.dx < 0) perp = -perp;
  } else if ((perp.dy < 0) != north) {
    perp = -perp;
  }
  return (a + b) / 2 + perp * (len * 0.25);
}

Future<ui.Image> paintRegionMap(
  RegionFrame frame,
  WorldOutline outline, {
  int px = CoupleWidgetConfig.imagePx,
}) {
  final rec = ui.PictureRecorder();
  RegionMapPainter(
    frame: frame,
    outline: outline,
  ).paint(Canvas(rec), Size.square(px.toDouble()));
  final picture = rec.endRecording();
  return picture.toImage(px, px).whenComplete(picture.dispose);
}

/// PNG bytes for the App Group (spec §3.3: 480 × 480, transparent sea).
Future<Uint8List> renderRegionMap(
  RegionFrame frame,
  WorldOutline outline, {
  int px = CoupleWidgetConfig.imagePx,
}) async {
  final img = await paintRegionMap(frame, outline, px: px);
  try {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('png encode failed');
    return data.buffer.asUint8List();
  } finally {
    img.dispose();
  }
}
