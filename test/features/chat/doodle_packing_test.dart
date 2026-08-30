import 'package:attune/features/chat/presentation/widgets/doodle_packing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(390, 844);

void main() {
  test('packs a dense field, not a handful of motifs', () {
    final placements = packDoodles(area: _size, assetCount: 14, seed: 7);

    // The reference is a tightly packed field. Six hand-placed motifs
    // cannot look like it at any scale.
    expect(placements.length, greaterThanOrEqualTo(40));
  });

  test('is deterministic for a seed — the wallpaper must not reshuffle', () {
    final a = packDoodles(area: _size, assetCount: 14, seed: 7);
    final b = packDoodles(area: _size, assetCount: 14, seed: 7);

    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].rect, b[i].rect);
      expect(a[i].assetIndex, b[i].assetIndex);
      expect(a[i].turns, b[i].turns);
    }
  });

  test('different seeds give different fields', () {
    final a = packDoodles(area: _size, assetCount: 14, seed: 1);
    final b = packDoodles(area: _size, assetCount: 14, seed: 2);
    expect(a.first.rect, isNot(b.first.rect));
  });

  test('placements never overlap', () {
    // Checked across many seeds AND a small area: on a roomy phone the
    // jittered grid rarely collides on its own, so a single seed passes
    // even with the overlap guard removed. A cramped field forces the
    // guard to actually do work.
    for (final area in [_size, const Size(160, 200), const Size(120, 120)]) {
      for (var seed = 0; seed < 25; seed++) {
        final field = packDoodles(area: area, assetCount: 14, seed: seed);
        for (var i = 0; i < field.length; i++) {
          for (var j = i + 1; j < field.length; j++) {
            expect(
              field[i].rect.overlaps(field[j].rect),
              isFalse,
              reason: 'seed $seed on $area: placement $i overlaps $j',
            );
          }
        }
      }
    }

    final placements = packDoodles(area: _size, assetCount: 14, seed: 3);

    for (var i = 0; i < placements.length; i++) {
      for (var j = i + 1; j < placements.length; j++) {
        expect(
          placements[i].rect.overlaps(placements[j].rect),
          isFalse,
          reason:
              'placement $i overlaps $j — the reference reads as dense '
              'but never collides',
        );
      }
    }
  });

  test('every placement stays inside the area', () {
    final placements = packDoodles(area: _size, assetCount: 14, seed: 5);
    final bounds = Offset.zero & _size;

    for (final p in placements) {
      expect(bounds.contains(p.rect.topLeft), isTrue);
      expect(bounds.contains(p.rect.bottomRight), isTrue);
    }
  });

  test('sizes vary — a uniform grid does not read as hand-drawn', () {
    final placements = packDoodles(area: _size, assetCount: 14, seed: 11);
    final widths = placements.map((p) => p.rect.width).toSet();
    expect(widths.length, greaterThan(3));
  });

  test('every asset gets used when the field is large enough', () {
    final placements = packDoodles(area: _size, assetCount: 14, seed: 13);
    final used = placements.map((p) => p.assetIndex).toSet();
    expect(used.length, 14);
  });

  test('a subset is marked animated, and the rest stay still', () {
    // All-animated would be noise behind a conversation; none would miss
    // the point. The split is what makes it feel alive but calm.
    final placements = packDoodles(area: _size, assetCount: 14, seed: 17);
    final animated = placements.where((p) => p.isAnimated).length;

    expect(animated, greaterThan(0));
    expect(animated, lessThan(placements.length));
  });
}
