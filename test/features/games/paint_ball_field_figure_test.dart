import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_figure.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart'
    show kPaintBallCoverWidth, kPaintBallPositions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    }) => MaterialApp(
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
                  rowHeight: 92,
                  ownerColor: const Color(0xFF5EEAD4),
                  isAiming: isAiming,
                  tilt: 0,
                  reduceMotion: reduceMotion,
                ),
              ],
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

    testWidgets('a figure that is not the fire control ignores taps', (
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
        find.descendant(
          of: find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });
  });
}
