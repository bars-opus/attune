import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each tier costs strictly less than the one above it', () {
    // The tiers exist to honour the thesis §6.10 launch gate on
    // representative Ghanaian hardware. A tier that is not actually
    // cheaper is a tier that does not help.
    expect(NeonQuality.plain.haloPasses, lessThan(NeonQuality.glow.haloPasses));
    expect(NeonQuality.glow.haloPasses, lessThan(NeonQuality.rich.haloPasses));

    expect(
      NeonQuality.plain.maxDroplets,
      lessThan(NeonQuality.glow.maxDroplets),
    );
    expect(
      NeonQuality.glow.maxDroplets,
      lessThan(NeonQuality.rich.maxDroplets),
    );
  });

  test('plain draws no halo at all', () {
    // Spec §3.1: under plain, halo passes collapse to a single stroke.
    // The outline must still be VISIBLE -- the game has to remain
    // playable, not merely cheap -- so this asserts the halo is gone,
    // not the stroke.
    expect(NeonQuality.plain.haloPasses, 0);
    expect(NeonQuality.plain.castsGroundLight, isFalse);
  });

  test('every tier still draws something', () {
    // A tier that renders nothing would make the field unplayable on
    // the hardware the tier exists to serve.
    for (final quality in NeonQuality.values) {
      expect(quality.maxDroplets, greaterThan(0));
    }
  });

  testWidgets('a subtree with no scope assumes the middle tier', (
    tester,
  ) async {
    // Defaulting to rich would punish exactly the devices the tiering
    // protects; defaulting to plain would make every screen that forgot
    // the scope look broken. The middle is the only safe default.
    late NeonQuality seen;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = neonQualityOf(context);
          return const SizedBox();
        },
      ),
    );

    expect(seen, NeonQuality.glow);
  });

  testWidgets('a scope overrides the default for its subtree', (tester) async {
    late NeonQuality seen;
    await tester.pumpWidget(
      NeonQualityScope(
        quality: NeonQuality.plain,
        child: Builder(
          builder: (context) {
            seen = neonQualityOf(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(seen, NeonQuality.plain);
  });

  testWidgets('a changed scope rebuilds its dependents', (tester) async {
    // Without this the tier would be latched at first build, and a
    // runtime downgrade after a jank measurement could never take
    // effect.
    final seen = <NeonQuality>[];
    Widget host(NeonQuality quality) => NeonQualityScope(
      quality: quality,
      child: Builder(
        builder: (context) {
          seen.add(neonQualityOf(context));
          return const SizedBox();
        },
      ),
    );

    await tester.pumpWidget(host(NeonQuality.rich));
    await tester.pumpWidget(host(NeonQuality.plain));

    expect(seen, [NeonQuality.rich, NeonQuality.plain]);
  });
}
