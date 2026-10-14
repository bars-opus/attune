import 'package:attune/features/games/paint_ball/presentation/widgets/field/cover_row.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_figure.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_ground.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_paint.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real app wraps everything in ScreenUtilInit at 375x812, so the
/// field must be measured inside one. Without it `.w` is the identity
/// function and a scaling bug is invisible -- which is exactly how the
/// six component test files missed it.
Widget _host(Widget child, {Size design = const Size(375, 812)}) =>
    ScreenUtilInit(
      designSize: design,
      builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('the field is built from its parts, not its own painters', (
    tester,
  ) async {
    // The point of the split: one file composes, six files draw. If the
    // field grew its own painters again this would start failing.
    await tester.pumpWidget(
      _host(
        const PaintBallField(
          splats: [],
          myPosition: 1,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FieldGround), findsOneWidget);
    expect(find.byType(FieldPaint), findsOneWidget);
    expect(
      find.byType(CoverRow),
      findsNWidgets(2),
      reason: 'two rows: yours and theirs',
    );
    expect(find.byKey(PaintBallFieldKeys.ground), findsOneWidget);
  });

  testWidgets('your row is the near one, whichever player you are', (
    tester,
  ) async {
    // The field never flips. "Mine is bottom, theirs is top" is learned
    // once rather than worked out each turn.
    await tester.pumpWidget(
      _host(
        const PaintBallField(
          splats: [],
          myPosition: 1,
          selectedShot: null,
          revealedPartnerPosition: 0,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mine = tester.getCenter(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: false)),
    );
    final theirs = tester.getCenter(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: true)),
    );

    expect(
      mine.dy,
      greaterThan(theirs.dy),
      reason: 'yours is nearer the bottom of the screen',
    );
  });

  group('the figure sits on its cover at real device widths', () {
    // DEVICE-REPORTED REGRESSION (old test 18), re-run under a real
    // ScreenUtilInit. The component test pinned raw pixels; this one
    // proves the SCALED units agree, which is the thing that actually
    // ships. If rowWidth is scaled and coverWidth is not -- or the
    // reverse -- the figure drifts off its cover exactly as it did on
    // the device that reported it.
    for (final width in [360.0, 375.0, 390.0, 430.0]) {
      testWidgets('at ${width.toInt()}pt', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        for (var position = 0; position < kPaintBallPositions; position++) {
          await tester.pumpWidget(
            _host(
              PaintBallField(
                splats: const [],
                myPosition: position,
                selectedShot: null,
                revealedPartnerPosition: null,
                isMyTurn: true,
                onSelectShot: (_) {},
                onSelectHide: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          final figure = tester.getRect(
            find.byKey(
              PaintBallFieldKeys.figure(position, isOpponent: false),
            ),
          );
          final bay = tester.getRect(
            find.byKey(PaintBallFieldKeys.bay(position, isOpponent: false)),
          );

          expect(
            (figure.center.dx - bay.center.dx).abs(),
            lessThan(1.0),
            reason:
                'at ${width.toInt()}pt the figure at position $position '
                'sits ${(figure.center.dx - bay.center.dx).abs().toStringAsFixed(1)}pt '
                'off the centre of its cover',
          );
        }
      });
    }
  });

  testWidgets('paint lands on the row it belongs to', (tester) async {
    // Addendum #5: the paint rows are fractions of the field's HEIGHT,
    // and nothing had checked them against where the covers actually
    // sit. A splat on your half must be nearer your row than theirs.
    await tester.pumpWidget(
      _host(
        const PaintBallField(
          splats: [
            PaintSplat(position: 1, isMine: true, hit: true, round: 1),
          ],
          myPosition: 1,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final layer = tester.widget<FieldPaint>(find.byType(FieldPaint));
    expect(layer.splats, hasLength(1), reason: 'a positive control');

    final paintBox = tester.getRect(find.byType(FieldPaint));
    final myBay = tester.getRect(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: false)),
    );

    final centre = splatCentre(
      splat: layer.splats.first,
      size: paintBox.size,
      rowWidth: paintBox.width,
    );

    expect(
      (centre.dx - (myBay.center.dx - paintBox.left)).abs(),
      lessThan(2.0),
      reason: 'paint lands on the column of the cover it hit',
    );
    expect(
      centre.dy,
      greaterThan(paintBox.height / 2),
      reason: 'your paint is on your half of the field',
    );
  });

  testWidgets('the public surface six other files import still exists', (
    tester,
  ) async {
    // paint_ball_provider.dart does `show kPaintBallPositions`, and the
    // history, knockout, battle, lobby screens and lives display all
    // import from this path. The split must not move any of them.
    expect(kPaintBallPositions, 3);
    expect(kPaintBallCoverWidth, greaterThan(0));
    expect(kPaintBallTargetScale, greaterThan(1));
    expect(paintBallPositionName(1), 'Middle');
    expect(PaintBallPalette.mine, isA<Color>());
    expect(
      PaintBallPalette.player,
      isA<Color>(),
      reason: 'history, knockout and battle screens still read this',
    );
    expect(
      const PaintSplat(position: 0, isMine: true, hit: false, round: 1)
          .position,
      0,
    );
  });

  testWidgets('reduce motion is taken from the platform, not a default', (
    tester,
  ) async {
    // The component widgets take `reduceMotion` as a plain bool, so the
    // composing field is the only place it can be read from the OS. If
    // it defaulted to false here, every accessibility guarantee below
    // would be silently off.
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (context, _) => MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: const Scaffold(
                  body: PaintBallField(
                    splats: [],
                    myPosition: 0,
                    selectedShot: null,
                    revealedPartnerPosition: null,
                    isMyTurn: true,
                  ),
                ),
              ),
            ),
      ),
    );
    await tester.pump();

    final rows = tester.widgetList<CoverRow>(find.byType(CoverRow));
    expect(rows, hasLength(2), reason: 'a positive control');
    for (final row in rows) {
      expect(
        row.reduceMotion,
        isTrue,
        reason: 'the field must read disableAnimations, not assume false',
      );
    }
  });

  testWidgets('a field with nothing chosen still renders', (tester) async {
    // Old test 2. The opening move, before anyone has acted.
    await tester.pumpWidget(
      _host(
        const PaintBallField(
          splats: [],
          myPosition: null,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(FieldFigure), findsNothing);
  });
}
