import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_figure.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_paint.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart'
    show PaintSplat, kPaintBallCoverWidth, kPaintBallPositions;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records draw calls so geometry is assertable without a golden.
class _RecordingCanvas implements Canvas {
  final paths = <Path>[];
  final circles = <Offset>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(c);

  @override
  noSuchMethod(Invocation invocation) => null;
}

void main() {
  const mine = Color(0xFF5EEAD4);
  const theirs = Color(0xFFFF4D6A);

  group('where paint lands', () {
    test('a hit lands on the centre of the cover it hit', () {
      // PRE-EXISTING BUG, fixed here. The old painter used
      // `size.width / kPaintBallPositions` slot maths while the bays and
      // figures use the cover-centre formula. The two agree only at the
      // middle position; at the outer two, paint landed 11-17pt to one
      // side of the cover it had just hit, worsening with screen width.
      //
      // Position 1 being exact is almost certainly why nobody caught it.
      for (final rowWidth in [360.0, 390.0, 430.0]) {
        final size = Size(rowWidth, 400);

        for (var position = 0; position < kPaintBallPositions; position++) {
          final expected = figureCentreX(
            rowWidth: rowWidth,
            coverWidth: kPaintBallCoverWidth,
            column: position.toDouble(),
          );

          final centre = splatCentre(
            splat: PaintSplat(
              position: position,
              isMine: true,
              // A hit has no random scatter, so its centre is exactly
              // the cover's -- which is what makes this checkable.
              hit: true,
              round: 1,
            ),
            size: size,
            rowWidth: rowWidth,
          );

          expect(
            centre.dx,
            closeTo(expected, 0.001),
            reason:
                'at width $rowWidth a hit on cover $position must land on '
                'that cover, not on a notional slot centre',
          );
        }
      }
    });

    test('slot maths would have failed this', () {
      // Pins the bug so a "simplification" back to width/3 breaks
      // loudly rather than silently reintroducing the drift.
      const rowWidth = 430.0;
      const position = 2;

      final slotCentre =
          rowWidth / kPaintBallPositions * position +
          rowWidth / kPaintBallPositions / 2;

      final centre = splatCentre(
        splat: const PaintSplat(
          position: position,
          isMine: true,
          hit: true,
          round: 1,
        ),
        size: const Size(rowWidth, 400),
        rowWidth: rowWidth,
      );

      expect(
        centre.dx,
        isNot(closeTo(slotCentre, 1.0)),
        reason: 'the two formulas genuinely disagree at this width',
      );
      expect(
        (centre.dx - slotCentre).abs(),
        greaterThan(15),
        reason: 'and they disagree by the measured 17pt, not by a rounding',
      );
    });

    test('a miss scatters, a hit does not', () {
      // A miss landing exactly on the cover would read as a hit. The
      // scatter is seeded, so it is deterministic per round+position --
      // the same round redrawn must not move its paint.
      Offset at({required bool hit}) => splatCentre(
        splat: PaintSplat(
          position: 0,
          isMine: true,
          hit: hit,
          round: 4,
        ),
        size: const Size(390, 400),
        rowWidth: 390,
      );

      final hitCentre = at(hit: true);
      final missCentre = at(hit: false);

      expect(
        missCentre.dx,
        isNot(closeTo(hitCentre.dx, 0.5)),
        reason: 'a miss must not land on the cover',
      );
      expect(
        at(hit: false).dx,
        closeTo(missCentre.dx, 0.001),
        reason: 'the scatter is seeded, so a redraw is stable',
      );
    });

    test('each side paints on its own half', () {
      // Yours near the bottom, theirs near the top -- the same
      // never-flips rule the rows follow.
      final mineAt = splatCentre(
        splat: const PaintSplat(
          position: 1,
          isMine: true,
          hit: true,
          round: 1,
        ),
        size: const Size(390, 400),
        rowWidth: 390,
      );
      final theirsAt = splatCentre(
        splat: const PaintSplat(
          position: 1,
          isMine: false,
          hit: true,
          round: 1,
        ),
        size: const Size(390, 400),
        rowWidth: 390,
      );

      expect(mineAt.dy, greaterThan(theirsAt.dy));
    });

    test('an out-of-range position lands on the nearest valid cover', () {
      // Review Focus #5. PaintSplat.position is a bare int off the wire
      // with no validation, so a stale or malformed round could carry 3
      // or -1.
      //
      // Asserting "stays on the field" was not enough: splatCentre also
      // clamps the returned dx, and that clamp rescues a bad position on
      // its own -- so the test passed even with the position clamp
      // deleted. This pins the clamp that actually matters.
      Offset at(int position) => splatCentre(
        splat: PaintSplat(
          position: position,
          isMine: true,
          hit: true,
          round: 1,
        ),
        size: const Size(390, 400),
        rowWidth: 390,
      );

      expect(at(3).dx, closeTo(at(2).dx, 0.001), reason: '3 clamps to 2');
      expect(at(99).dx, closeTo(at(2).dx, 0.001), reason: '99 clamps to 2');
      expect(at(-1).dx, closeTo(at(0).dx, 0.001), reason: '-1 clamps to 0');

      for (final position in [-1, 3, 99]) {
        expect(at(position).dx.isFinite, isTrue, reason: 'position $position');
      }
    });
  });

  group('the paint layer', () {
    test('an empty list draws nothing at all', () {
      // Old test 22, and the reason it matters is fairness rather than
      // tidiness: accumulated paint is a map of where your partner has
      // already fired -- their habits readable for free, which is the
      // clue this game asks you to earn. A board between rounds is
      // clean, and this is the assertion that keeps it so.
      final canvas = _RecordingCanvas();
      FieldPaintPainter(
        splats: const [],
        mineColor: mine,
        theirsColor: theirs,
        quality: NeonQuality.glow,
        rowWidth: 390,
      ).paint(canvas, const Size(390, 400));

      expect(canvas.paths, isEmpty);
      expect(canvas.circles, isEmpty);
    });

    test('a non-empty list does draw — the positive control', () {
      // Without this, the test above could pass because the painter is
      // broken rather than because the list is empty. that exact
      // vacuous shape has been found seven times in this codebase.
      final canvas = _RecordingCanvas();
      FieldPaintPainter(
        splats: const [
          PaintSplat(position: 1, isMine: true, hit: true, round: 1),
        ],
        mineColor: mine,
        theirsColor: theirs,
        quality: NeonQuality.glow,
        rowWidth: 390,
      ).paint(canvas, const Size(390, 400));

      expect(canvas.paths, isNotEmpty);
    });

    test('a long match draws a bounded number of splats', () {
      // Paint from 40 rounds would bury the covers. The painter keeps
      // only the most recent, and the cap must hold rather than growing
      // with the match.
      final canvas = _RecordingCanvas();
      FieldPaintPainter(
        splats: [
          for (var round = 0; round < 40; round++)
            PaintSplat(
              position: round % kPaintBallPositions,
              isMine: round.isEven,
              hit: round % 3 == 0,
              round: round,
            ),
        ],
        mineColor: mine,
        theirsColor: theirs,
        quality: NeonQuality.glow,
        rowWidth: 390,
      ).paint(canvas, const Size(390, 400));

      expect(canvas.paths, isNotEmpty);
      expect(
        canvas.paths.length,
        kFieldPaintVisible,
        reason: 'exactly the cap, not merely at most it -- a cap of 1 would '
            'satisfy an upper bound while hiding most of the match',
      );
    });

    test('the plain tier skips the flecks, which is the saving', () {
      // The tiering exists to honour a launch gate on low-end hardware,
      // and three extra circles per splat twelve splats deep is exactly
      // the cost it is about. Without this test, deleting the flecks
      // outright would leave every other test green.
      const splats = [
        PaintSplat(position: 1, isMine: true, hit: true, round: 1),
      ];

      _RecordingCanvas render(NeonQuality quality) {
        final canvas = _RecordingCanvas();
        FieldPaintPainter(
          splats: splats,
          mineColor: mine,
          theirsColor: theirs,
          quality: quality,
          rowWidth: 390,
        ).paint(canvas, const Size(390, 400));
        return canvas;
      }

      final glow = render(NeonQuality.glow);
      final plain = render(NeonQuality.plain);

      expect(
        glow.circles,
        hasLength(3),
        reason: 'a positive control: three flecks per splat on glow',
      );
      expect(plain.circles, isEmpty, reason: 'plain draws no flecks');

      // The blob itself survives on both -- degrading drops decoration,
      // never the paint.
      expect(plain.paths, hasLength(glow.paths.length));
      expect(plain.paths, isNotEmpty);
    });

    test('a zero-sized field does not throw', () {
      final canvas = _RecordingCanvas();
      expect(
        () => FieldPaintPainter(
          splats: const [
            PaintSplat(position: 0, isMine: true, hit: true, round: 1),
          ],
          mineColor: mine,
          theirsColor: theirs,
          quality: NeonQuality.glow,
          rowWidth: 0,
        ).paint(canvas, Size.zero),
        returnsNormally,
      );
    });

    testWidgets('the layer exposes its splats without a dynamic read', (
      tester,
    ) async {
      // Spec §3.6.1: the old test reached through
      // `(painter as dynamic).splats`, and worse, filtered painters by
      // type NAME -- so after a rename the loop ran zero times and the
      // test passed having asserted nothing.
      await tester.pumpWidget(
        ScreenUtilInit(
          // The widget layer scales, so it needs an init in the tree.
          // The pure splatCentre/FieldPaintPainter tests above
          // deliberately do not -- that is why coverWidth is a
          // parameter rather than a `.w` call inside them.
          designSize: const Size(375, 812),
          builder:
              (context, _) => const MaterialApp(
                home: Scaffold(
                  body: FieldPaint(
                    splats: [],
                    mineColor: mine,
                    theirsColor: theirs,
                  ),
                ),
              ),
        ),
      );
      await tester.pump();

      // Found by type rather than by key: the key sits on the inner
      // CustomPaint, which is where a painter lookup wants it, so
      // find.byKey would hand back the CustomPaint and not the layer.
      final layer = tester.widget<FieldPaint>(find.byType(FieldPaint));

      expect(layer.splats, isEmpty);

      // And the key IS present, so the field can locate this layer.
      expect(find.byKey(PaintBallFieldKeys.paint), findsOneWidget);
    });
  });
}
