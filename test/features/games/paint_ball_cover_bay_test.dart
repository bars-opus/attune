import 'dart:math';

import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/cover_bay.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records drawn paths so bay geometry can be asserted without a golden.
class _RecordingCanvas implements Canvas {
  final paths = <Path>[];
  final paints = <Paint>[];

  @override
  void drawPath(Path path, Paint paint) {
    paths.add(path);
    paints.add(paint);
  }

  @override
  noSuchMethod(Invocation invocation) => null;
}

CoverBayPaintContext _context({
  CoverBayState state = CoverBayState.rest,
  bool facing = true,
  NeonQuality quality = NeonQuality.glow,
}) => CoverBayPaintContext(
  state: state,
  facing: facing,
  ownerColor: const Color(0xFF5EEAD4),
  quality: quality,
);

void main() {
  const style = DarknessCoverStyle();
  const size = Size(74, 62);

  test('a bay at rest is drawn, dim', () {
    // Structure is tier 2 of §2.1: present, not shouting. It must still
    // be VISIBLE -- a player has to see where the three hiding places
    // are before choosing one.
    final canvas = _RecordingCanvas();
    style.paint(canvas, size, _context());

    expect(canvas.paints, isNotEmpty, reason: 'a positive control');
    for (final paint in canvas.paints) {
      expect(paint.color.a, greaterThan(0));
    }
  });

  test('an aimed bay is unmistakably brighter than one at rest', () {
    // Stage 2 addendum #2. With no Fire button, the aimed cover IS the
    // confirmation that a target is chosen, so the difference cannot be
    // a subtle tint. The old renderer slid the whole shield aside and
    // doubled its opacity; a bay that only brightened slightly would
    // lose the game's only commit affordance.
    final rest = _RecordingCanvas();
    final aimed = _RecordingCanvas();
    style.paint(rest, size, _context());
    style.paint(aimed, size, _context(state: CoverBayState.aimed));

    double peak(_RecordingCanvas canvas) =>
        canvas.paints.map((paint) => paint.color.a).reduce(max);

    expect(rest.paints, isNotEmpty);
    expect(aimed.paints, isNotEmpty);
    expect(
      peak(aimed),
      greaterThan(peak(rest) * 1.5),
      reason: 'aimed must read as committed at a glance, not as a tint',
    );
  });

  test('an aimed bay opens its mouth wider than one at rest', () {
    // The neon equivalent of the shield sliding aside: the legs part, so
    // the shot has a visible path through. "You can see the path for the
    // shot" is the property the original slide was built for.
    final rest = _RecordingCanvas();
    final aimed = _RecordingCanvas();
    style.paint(rest, size, _context());
    style.paint(aimed, size, _context(state: CoverBayState.aimed));

    expect(rest.paths, isNotEmpty);
    expect(aimed.paths, isNotEmpty);
    expect(
      aimed.paths.first.getBounds().width,
      greaterThan(rest.paths.first.getBounds().width),
      reason: 'an opened gate is wider than a closed one',
    );
  });

  test('the two rows face opposite ways', () {
    // DEVICE-REPORTED REGRESSION (old test 19). Both rows once domed the
    // same way, so the opponent's cover looked like it sheltered someone
    // standing off the top of the board rather than facing you across
    // the line. `facing` replaces the old painter's `opensDown` with the
    // same polarity: true is the viewer's own row, legs below the dome.
    final mine = _RecordingCanvas();
    final theirs = _RecordingCanvas();
    style.paint(mine, size, _context(facing: true));
    style.paint(theirs, size, _context(facing: false));

    expect(mine.paths, isNotEmpty);
    expect(theirs.paths, isNotEmpty);

    // The arch's crown sits at opposite ends of the box. Comparing the
    // vertical centroid of the bounds is enough to tell them apart, and
    // unlike an eyeball check it cannot be fooled by a mirror image.
    final mineCentre = mine.paths.first.getBounds().center.dy;
    final theirsCentre = theirs.paths.first.getBounds().center.dy;
    expect(
      mineCentre,
      isNot(closeTo(theirsCentre, 0.5)),
      reason: 'exactly one row faces the other',
    );
  });

  test('the painter exposes facing publicly rather than via dynamic', () {
    // Spec §3.6.1: the old test read `(painter as dynamic).opensDown`,
    // so a rename broke it with no behaviour change. This is the typed
    // replacement.
    final painter = CoverBayPainter(
      state: CoverBayState.rest,
      facing: false,
      ownerColor: const Color(0xFF5EEAD4),
      quality: NeonQuality.glow,
      style: style,
    );

    expect(painter.facing, isFalse);
    expect(painter.state, CoverBayState.rest);
  });

  test('a zero-sized bay does not throw', () {
    // Reachable during a route transition, when a collapsed parent hands
    // down a zero box.
    final canvas = _RecordingCanvas();
    expect(
      () => style.paint(canvas, Size.zero, _context()),
      returnsNormally,
    );
  });

  test('the plain tier still draws the bay', () {
    // Degrading drops halo passes, never the outline. A bay nobody can
    // see is three invisible hiding places -- unplayable on exactly the
    // hardware the tiering exists to serve.
    final canvas = _RecordingCanvas();
    style.paint(canvas, size, _context(quality: NeonQuality.plain));

    expect(canvas.paints, isNotEmpty);
  });

  testWidgets('a bay carries its position-and-side key', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CoverBay(
            position: 1,
            isOpponent: true,
            state: CoverBayState.rest,
            ownerColor: Color(0xFFFF4D6A),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: true)),
      findsOneWidget,
    );
    expect(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: false)),
      findsNothing,
      reason: 'the key must distinguish the two rows',
    );
  });

  testWidgets('a custom style replaces the darkness without surgery', (
    tester,
  ) async {
    // §2.3 is explicitly provisional: cover-as-darkness is a bet, and
    // swapping it must be a new class rather than an edit to the field.
    // This proves the seam actually works.
    var painted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverBay(
            position: 0,
            isOpponent: false,
            state: CoverBayState.rest,
            ownerColor: const Color(0xFF5EEAD4),
            style: _ProbeStyle(() => painted = true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(painted, isTrue, reason: 'the injected style was used');
  });
}

class _ProbeStyle implements PaintBallCoverStyle {
  _ProbeStyle(this.onPaint);

  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size, CoverBayPaintContext context) =>
      onPaint();
}
