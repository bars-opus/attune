import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_figure.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart'
    show kPaintBallCoverWidth, kPaintBallPositions;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records drawn paths so the figure's geometry can be asserted without a
/// golden. Same idiom as the cover-bay test.
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

void main() {
  group('the centring formula', () {
    test('a figure sits on its cover at every width', () {
      // DEVICE-REPORTED REGRESSION (old test 18). The figure positioned
      // itself on notional slots (rowWidth / 3) while the covers are a
      // FIXED width laid out by spaceEvenly with four equal gaps. Those
      // two agree only when the row happens to be exactly three covers
      // wide; at any other width the figure drifted off its cover, worst
      // at the outer ones.
      //
      // Extracted as a pure function precisely so this is checkable
      // without pumping a field at three widths and reading back
      // rectangles.
      for (final rowWidth in [320.0, 360.0, 390.0, 430.0, 600.0]) {
        const coverWidth = 74.0;
        final gap =
            (rowWidth - kPaintBallPositions * coverWidth) /
            (kPaintBallPositions + 1);

        for (var position = 0; position < kPaintBallPositions; position++) {
          final expected =
              gap * (position + 1) + coverWidth * (position + 0.5);

          expect(
            figureCentreX(
              rowWidth: rowWidth,
              coverWidth: coverWidth,
              column: position.toDouble(),
            ),
            closeTo(expected, 0.001),
            reason:
                'at width $rowWidth position $position must land on its '
                'cover centre, not on a notional slot centre',
          );
        }
      }
    });

    test('a slot-centre formula would have failed this', () {
      // Pins WHY the formula is what it is. If someone simplifies it
      // back to rowWidth/3 maths, this test says what breaks.
      const rowWidth = 430.0;
      const coverWidth = 74.0;
      const position = 2.0;

      final slotCentre =
          rowWidth / kPaintBallPositions * position +
          rowWidth / kPaintBallPositions / 2;

      expect(
        figureCentreX(
          rowWidth: rowWidth,
          coverWidth: coverWidth,
          column: position,
        ),
        isNot(closeTo(slotCentre, 1.0)),
        reason: 'the two formulas genuinely disagree at this width',
      );
    });

    test('a fractional column interpolates, for the crossing', () {
      // Mid-journey the figure is between two columns. The formula has
      // to accept 1.5 and land halfway, or the travel would jump.
      const rowWidth = 390.0;
      const coverWidth = 74.0;

      final one = figureCentreX(
        rowWidth: rowWidth,
        coverWidth: coverWidth,
        column: 1,
      );
      final two = figureCentreX(
        rowWidth: rowWidth,
        coverWidth: coverWidth,
        column: 2,
      );
      final half = figureCentreX(
        rowWidth: rowWidth,
        coverWidth: coverWidth,
        column: 1.5,
      );

      expect(half, closeTo((one + two) / 2, 0.001));
    });

    test('a row narrower than its covers does not produce a NaN', () {
      // Defensive: a negative gap is arithmetically fine, but an
      // infinite or NaN result would throw inside Positioned. Reachable
      // on a very small screen or mid-animation layout.
      final x = figureCentreX(
        rowWidth: 100,
        coverWidth: 74,
        column: 2,
      );

      expect(x.isFinite, isTrue);
    });
  });

  group('the figure widget', () {
    Widget host({
      required int position,
      bool isOpponent = false,
      bool reduceMotion = false,
      bool isAiming = false,
      VoidCallback? onTap,
    }) => ScreenUtilInit(
      // The app wraps everything in ScreenUtilInit at 375x812, and the
      // field's sizes are scaled, so a test without one hits
      // LateInitializationError on the first `.w`. The legacy field test
      // has always wrapped this way; these component tests should too.
      designSize: const Size(375, 812),
      builder: (context, _) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: SizedBox(
            width: 390,
            height: 120,
            child: Stack(
              children: [
                FieldFigure(
                  position: position,
                  isOpponent: isOpponent,
                  rowWidth: 390,
                  coverWidth: kPaintBallCoverWidth,
                  ownerColor: const Color(0xFF5EEAD4),
                  isAiming: isAiming,
                  tilt: 0,
                  reduceMotion: reduceMotion,
                  onTap: onTap,
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );

    testWidgets('a figure carries its position-and-side key', (tester) async {
      await tester.pumpWidget(host(position: 1));
      await tester.pump();

      expect(
        find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)),
        findsOneWidget,
      );
      expect(
        find.byKey(PaintBallFieldKeys.figure(1, isOpponent: true)),
        findsNothing,
        reason: 'the key must distinguish the two rows',
      );
    });

    testWidgets('repositioning travels rather than teleporting', (
      tester,
    ) async {
      // Old test 16. Moving cover is a journey: the figure leaves,
      // crosses, and enters the new cover as ONE body. A cross-fade
      // between two covers would read as two figures, and taking cover
      // would feel like being reassigned rather than moving.
      await tester.pumpWidget(host(position: 0));
      await tester.pumpAndSettle();

      Offset centre() => tester.getCenter(
        find.byKey(PaintBallFieldKeys.figure(2, isOpponent: false)),
      );

      final start = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(0, isOpponent: false)))
          .dx;

      await tester.pumpWidget(host(position: 2));
      await tester.pump(const Duration(milliseconds: 310));
      final middle = centre().dx;

      await tester.pumpAndSettle();
      final end = centre().dx;

      expect(middle, greaterThan(start), reason: 'it has set off');
      expect(
        middle,
        lessThan(end),
        reason: 'it has not arrived yet -- it is travelling',
      );

      // Exactly one figure throughout: the same body moving, never a
      // second one fading in.
      expect(
        find.byWidgetPredicate((widget) => widget is FieldFigure),
        findsOneWidget,
      );
    });

    testWidgets('a journey interrupted mid-flight does not teleport', (
      tester,
    ) async {
      // Measured before the fix: retargeting at t=0.5 snapped the figure
      // 116pt forward to the abandoned target, then walked it backwards.
      await tester.pumpWidget(host(position: 0));
      await tester.pumpAndSettle();

      await tester.pumpWidget(host(position: 2));
      await tester.pump(const Duration(milliseconds: 310));
      final midJourney = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(2, isOpponent: false)))
          .dx;

      await tester.pumpWidget(host(position: 1));
      await tester.pump(const Duration(milliseconds: 1));
      final afterRetarget = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)))
          .dx;

      expect(
        (afterRetarget - midJourney).abs(),
        lessThan(8),
        reason:
            'a retarget continues from where the figure is; it must not '
            'jump to the target it was abandoning',
      );
    });

    testWidgets('the journey is long enough to be followed', (tester) async {
      // Stage 2 addendum #1: 620ms, deliberately outside the plan's
      // 150-320ms band. That band governs a SETTLE -- one object
      // arriving at one place. This is three sequential beats (back out
      // of cover, across, forward in), and three beats inside 320ms is
      // ~100ms each, below the point at which an eye can follow a path.
      //
      // Pinned as a constant so an implementer "fixing" it to comply
      // with the band breaks a test rather than the game's feel.
      expect(kFigureTravelDuration.inMilliseconds, 620);
    });

    testWidgets('reduce motion arrives immediately', (tester) async {
      await tester.pumpWidget(host(position: 0, reduceMotion: true));
      await tester.pumpAndSettle();

      final start = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(0, isOpponent: false)))
          .dx;

      await tester.pumpWidget(host(position: 2, reduceMotion: true));
      await tester.pump();

      final after = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(2, isOpponent: false)))
          .dx;

      expect(
        after,
        greaterThan(start),
        reason: 'it moved',
      );

      // And it is ALREADY there -- no further frames needed.
      await tester.pumpAndSettle();
      expect(
        tester
            .getCenter(
              find.byKey(PaintBallFieldKeys.figure(2, isOpponent: false)),
            )
            .dx,
        closeTo(after, 0.001),
        reason: 'reduce motion jumps to the end state, it does not animate',
      );
    });

    testWidgets('a travelling figure steps clear of cover', (tester) async {
      // Old test 17. Sliding sideways while still tucked in would read
      // as passing through the wall, so the crossing happens stepped
      // out. Your row is at the bottom, so stepping out moves UP the
      // screen -- a smaller dy.
      await tester.pumpWidget(host(position: 0));
      await tester.pumpAndSettle();

      final atRest = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(0, isOpponent: false)))
          .dy;

      await tester.pumpWidget(host(position: 2));
      await tester.pump(const Duration(milliseconds: 310));

      final crossing = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(2, isOpponent: false)))
          .dy;

      expect(
        crossing,
        lessThan(atRest),
        reason: 'the crossing happens clear of cover, not through it',
      );
    });

    testWidgets('an aiming figure steps out of cover', (tester) async {
      // An aiming player is deliberately exposed, so it stands above its
      // cover rather than tucked in. Your row is at the bottom: stepped
      // out means a smaller dy.
      await tester.pumpWidget(host(position: 0));
      await tester.pumpAndSettle();
      final tuckedIn = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(0, isOpponent: false)))
          .dy;

      await tester.pumpWidget(host(position: 0, isAiming: true));
      await tester.pumpAndSettle();
      final aiming = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(0, isOpponent: false)))
          .dy;

      expect(aiming, lessThan(tuckedIn));
    });

    testWidgets('the opponent figure is keyed to its side and sits from top', (
      tester,
    ) async {
      // The opponent's row shelters under the far dome, so it positions
      // from the top edge, not from the bottom.
      //
      // The inset is 46.h rather than a raw 46: the field scales with
      // ScreenUtil like the rest of the app, so pinning the design-unit
      // constant would fail on every device that is not 375pt wide.
      await tester.pumpWidget(host(position: 1, isOpponent: true));
      await tester.pump();

      final key = PaintBallFieldKeys.figure(1, isOpponent: true);
      expect(find.byKey(key), findsOneWidget);

      final positioned = tester.widget<Positioned>(find.byKey(key));
      expect(
        positioned.top,
        closeTo(46.h, 0.01),
        reason: 'the opponent sits in from the top, in scaled units',
      );
      expect(positioned.bottom, isNull);
    });

    testWidgets('the two rows point opposite ways', (tester) async {
      // Confirmed at widget level: the player's row points up, the
      // opponent's points down, so the two rows face each other.
      await tester.pumpWidget(host(position: 1));
      await tester.pump();
      final mine = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter as FieldFigurePainter;

      await tester.pumpWidget(host(position: 1, isOpponent: true));
      await tester.pump();
      final theirs = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(PaintBallFieldKeys.figure(1, isOpponent: true)),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter as FieldFigurePainter;

      expect(mine.pointsUp, isTrue);
      expect(theirs.pointsUp, isFalse);
    });

    testWidgets('a figure that is not the fire control is transparent to taps', (
      tester,
    ) async {
      // It stands over a cover that is itself a tap target. Intercepting
      // taps when it is not the fire control would make that cover
      // unreachable -- silently costing the player one of their three
      // hiding places.
      await tester.pumpWidget(host(position: 1));
      await tester.pump();

      final figure = tester.widget<FieldFigure>(
        find.byWidgetPredicate((widget) => widget is FieldFigure),
      );

      expect(figure.onTap, isNull);
      expect(
        tester
            .widget<IgnorePointer>(
              find.descendant(
                of: find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)),
                matching: find.byType(IgnorePointer),
              ),
            )
            .ignoring,
        isTrue,
        reason: 'it must be transparent to taps, or it steals the cover '
            'beneath it and silently costs a hiding place',
      );
    });

    testWidgets('the fire control receives taps and fires its callback', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(host(position: 1, onTap: () => taps++));
      await tester.pump();

      expect(
        tester
            .widget<IgnorePointer>(
              find.descendant(
                of: find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)),
                matching: find.byType(IgnorePointer),
              ),
            )
            .ignoring,
        isFalse,
      );

      await tester.tap(find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)));
      expect(taps, 1);
    });
  });

  group('the figure painter', () {
    const figureSize = Size(22, 20);
    const owner = Color(0xFF5EEAD4);

    FieldFigurePainter painterFor({
      bool pointsUp = true,
      NeonQuality quality = NeonQuality.glow,
    }) => FieldFigurePainter(
      color: owner,
      pointsUp: pointsUp,
      quality: quality,
    );

    test('the fill is drawn in the owner colour', () {
      // §2.2: the figure wears its owner's hue. The first path drawn is
      // the solid fill; its colour must be the owner's, ignoring alpha.
      final canvas = _RecordingCanvas();
      painterFor().paint(canvas, figureSize);

      expect(canvas.paths, isNotEmpty, reason: 'a positive control');
      expect(
        canvas.paints.first.color.toARGB32() & 0xFFFFFF,
        owner.toARGB32() & 0xFFFFFF,
      );
      expect(canvas.paints.first.color.a, greaterThan(0));
    });

    test('an upward figure has its apex at the top, a downward one at the base', () {
      // Point (2, 18) lies inside the upward triangle (its base is wide
      // there) and outside the downward one (its apex is at the bottom,
      // so the top-left corner is empty).
      final up = _RecordingCanvas();
      painterFor().paint(up, figureSize);
      final down = _RecordingCanvas();
      painterFor(pointsUp: false).paint(down, figureSize);

      expect(up.paths.first.contains(const Offset(2, 18)), isTrue);
      expect(down.paths.first.contains(const Offset(2, 18)), isFalse);
    });

    test('the plain tier draws strictly fewer paths than glow', () {
      // §6.10: degrading drops the halo passes. If plain drew as many
      // paths as glow, the saving would be fiction.
      final glow = _RecordingCanvas();
      painterFor().paint(glow, figureSize);
      final plain = _RecordingCanvas();
      painterFor(quality: NeonQuality.plain).paint(plain, figureSize);

      expect(plain.paths.length, lessThan(glow.paths.length));
    });
  });
}
