import 'package:attune/features/games/paint_ball/presentation/widgets/field/cover_bay.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/cover_row.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_figure.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart'
    show kPaintBallPositions;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    bool isOpponent = false,
    int? hiddenAt,
    int? aimedAt,
    bool enabled = true,
    bool emerged = true,
    ValueChanged<int>? onTap,
    VoidCallback? onTapFigure,
  }) => ScreenUtilInit(
    // The app wraps everything in ScreenUtilInit at 375x812 and the
    // field's sizes are scaled, so a test without one throws
    // LateInitializationError on the first `.w`. The legacy field test
    // has always wrapped this way.
    designSize: const Size(375, 812),
    builder: (context, _) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        // Scaled, like the cover width the row computes. A raw 390 here
        // against a scaled coverWidth is mixed units: three 158pt covers
        // cannot fit a 390pt row, the gap goes negative and the figure
        // drifts off its cover -- which is exactly the device-reported
        // bug the centring test exists to catch.
        width: 390.w,
        height: 120.h,
        child: CoverRow(
          isOpponent: isOpponent,
          hiddenAt: hiddenAt,
          aimedAt: aimedAt,
          enabled: enabled,
          emerged: emerged,
          ownerColor: const Color(0xFF5EEAD4),
          reduceMotion: false,
          onTap: onTap,
          onTapFigure: onTapFigure,
        ),
      ),
    ),
    ),
  );

  testWidgets('every position is labelled for a screen reader', (
    tester,
  ) async {
    // Old tests 3 and 10. Named by POSITION rather than index: a
    // screen-reader user hears "Middle target", which is the thing on
    // the board, not "cover 2", which is an implementation detail.
    //
    // These labels are also the only hooks a renderer rewrite cannot
    // invalidate -- they are an accessibility contract, so they outlive
    // every painter rename.
    await tester.pumpWidget(host(isOpponent: true));
    await tester.pump();

    expect(find.bySemanticsLabel('Left target'), findsOneWidget);
    expect(find.bySemanticsLabel('Middle target'), findsOneWidget);
    expect(find.bySemanticsLabel('Right target'), findsOneWidget);
  });

  testWidgets('your own row is cover, theirs is a target', (tester) async {
    // The asymmetry in the words matters: you hide behind cover, you
    // shoot at a target. One row cannot be mistaken for the other by a
    // screen reader any more than by an eye.
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.bySemanticsLabel('Middle cover'), findsOneWidget);
    expect(find.bySemanticsLabel('Middle target'), findsNothing);
  });

  testWidgets('a tap reports which position was chosen', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(host(isOpponent: true, onTap: taps.add));
    await tester.pump();

    for (var i = 0; i < kPaintBallPositions; i++) {
      await tester.tap(
        find.bySemanticsLabel('${['Left', 'Middle', 'Right'][i]} target'),
      );
    }
    await tester.pump();

    expect(taps, [0, 1, 2]);
  });

  testWidgets('nothing is selectable when the row is disabled', (
    tester,
  ) async {
    // Old test 5. A player must not be able to move out of turn.
    var tapped = false;
    await tester.pumpWidget(
      host(isOpponent: true, enabled: false, onTap: (_) => tapped = true),
    );
    await tester.pump();

    final detectors = find.byType(GestureDetector);
    expect(
      detectors.evaluate().length,
      greaterThanOrEqualTo(kPaintBallPositions),
      reason:
          'a positive control: without this the taps below could be '
          'tapping nothing at all',
    );

    for (final target in detectors.evaluate()) {
      await tester.tap(find.byWidget(target.widget), warnIfMissed: false);
    }
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets('the same row is selectable when enabled', (tester) async {
    // Mirror of the disabled case: proves the difference is the enabled
    // flag, not a null callback or a finder that matches nothing.
    final taps = <int>[];
    await tester.pumpWidget(
      host(isOpponent: true, enabled: true, onTap: taps.add),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: true)),
    );
    await tester.pump();

    expect(taps, [1]);
  });

  testWidgets('exactly three bays are drawn, all keyed to this side', (
    tester,
  ) async {
    await tester.pumpWidget(host(isOpponent: true));
    await tester.pump();

    for (var i = 0; i < kPaintBallPositions; i++) {
      expect(
        find.byKey(PaintBallFieldKeys.bay(i, isOpponent: true)),
        findsOneWidget,
      );
      expect(
        find.byKey(PaintBallFieldKeys.bay(i, isOpponent: false)),
        findsNothing,
        reason: 'a row must not render the other side’s bays',
      );
    }
  });

  testWidgets('only the aimed bay is in the aimed state', (tester) async {
    // With no Fire button the aimed cover IS the confirmation that a
    // target is chosen, so exactly one may claim it. Two aimed bays
    // would make the commit ambiguous.
    await tester.pumpWidget(host(isOpponent: true, aimedAt: 2));
    await tester.pump();

    final states = <int, CoverBayState>{};
    for (var i = 0; i < kPaintBallPositions; i++) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(PaintBallFieldKeys.bay(i, isOpponent: true)),
          matching: find.byType(CustomPaint),
          matchRoot: true,
        ),
      );
      states[i] = (paint.painter! as CoverBayPainter).state;
    }

    expect(states[2], CoverBayState.aimed);
    expect(states[0], CoverBayState.rest);
    expect(states[1], CoverBayState.rest);
  });

  testWidgets('a screen reader is told which target is chosen', (
    tester,
  ) async {
    // With no Fire button the aimed bay is the ONLY confirmation that a
    // target is chosen. A sighted player gets it from the bay widening
    // and brightening; without `selected` a screen-reader user got
    // nothing at all. Caught by the final whole-branch review after
    // being deferred once.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(host(isOpponent: true, aimedAt: 2));
    await tester.pump();

    final aimed = tester.getSemantics(
      find.bySemanticsLabel('Right target'),
    );
    final notAimed = tester.getSemantics(
      find.bySemanticsLabel('Left target'),
    );

    expect(
      aimed.hasFlag(SemanticsFlag.isSelected),
      isTrue,
      reason: 'the chosen target announces itself as chosen',
    );
    expect(
      notAimed.hasFlag(SemanticsFlag.isSelected),
      isFalse,
      reason: 'and the others do not -- a positive control for the above',
    );

    handle.dispose();
  });

  testWidgets('a bay that is both aimed at and occupied reads as aimed', (
    tester,
  ) async {
    // With no Fire button the aimed bay is the player's only
    // confirmation that a target is chosen, so "somebody is standing
    // here" must not outvote it. Without this case, swapping the first
    // two branches of _stateFor passes every other test.
    await tester.pumpWidget(host(isOpponent: true, hiddenAt: 2, aimedAt: 2));
    await tester.pump();

    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(PaintBallFieldKeys.bay(2, isOpponent: true)),
        matching: find.byType(CustomPaint),
        matchRoot: true,
      ),
    );

    expect((paint.painter! as CoverBayPainter).state, CoverBayState.aimed);
  });

  testWidgets('a hidden occupant puts exactly one figure on the row', (
    tester,
  ) async {
    // Old tests 6 and 7. You can see where YOU are hiding; their
    // position appears only after a round resolves. One figure, not one
    // per cover.
    await tester.pumpWidget(host(hiddenAt: 1));
    await tester.pump();

    expect(
      find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)),
      findsOneWidget,
    );
    expect(find.byType(FieldFigure), findsOneWidget);
  });

  testWidgets('a figure is absent until it has emerged', (tester) async {
    // During the replay's first beat both players are still behind
    // cover. The figure is omitted rather than hidden, which means its
    // travel state unmounts -- so emerging is a pop-in, not a step-out.
    // Pinned as the current behaviour so the replay task inherits a
    // fact rather than a surprise.
    await tester.pumpWidget(host(hiddenAt: 1, emerged: false));
    await tester.pump();

    expect(find.byType(FieldFigure), findsNothing);

    await tester.pumpWidget(host(hiddenAt: 1));
    await tester.pump();

    expect(find.byType(FieldFigure), findsOneWidget);
  });

  testWidgets('no occupant means no figure at all', (tester) async {
    // The hidden information the whole game turns on. If their figure
    // were drawn before the reveal, the guess would stop being a guess.
    await tester.pumpWidget(host(isOpponent: true));
    await tester.pump();

    expect(find.byType(FieldFigure), findsNothing);
  });

  testWidgets('the figure stands on the centre of its own cover', (
    tester,
  ) async {
    // DEVICE-REPORTED REGRESSION (old test 18), now checked through the
    // composition rather than the formula alone -- the formula is unit
    // tested in its own task, but a correct formula wired to the wrong
    // cover width would still drift. Both sides are checked: the
    // opponent's covers are scaled by kPaintBallTargetScale, so a row
    // that drops the scale drifts only on that side.
    for (final isOpponent in [false, true]) {
      for (final width in [360.0, 390.0, 430.0]) {
        // The view IS the width under test, so ScreenUtil's design size
        // matches it and `.w` is 1:1. That keeps rowWidth and coverWidth
        // in the same units -- mixing them is the bug this test catches,
        // and a scaled coverWidth against a raw rowWidth drifts the
        // figure 28pt off its cover.
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        for (final position in [0, 2]) {
          await tester.pumpWidget(
            ScreenUtilInit(
              designSize: Size(width, 900),
              builder: (context, _) => MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: width,
                  height: 120,
                  child: CoverRow(
                    isOpponent: isOpponent,
                    hiddenAt: position,
                    aimedAt: null,
                    enabled: true,
                    ownerColor: const Color(0xFF5EEAD4),
                    reduceMotion: true,
                    onTap: (_) {},
                  ),
                ),
              ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final figure = tester.getRect(
            find.byKey(
              PaintBallFieldKeys.figure(position, isOpponent: isOpponent),
            ),
          );
          final bay = tester.getRect(
            find.byKey(PaintBallFieldKeys.bay(position, isOpponent: isOpponent)),
          );

          expect(
            (figure.center.dx - bay.center.dx).abs(),
            lessThan(1.0),
            reason:
                '${isOpponent ? 'opponent' : 'own'} row at width $width, '
                'position $position: the figure sits '
                '${(figure.center.dx - bay.center.dx).abs().toStringAsFixed(1)}pt '
                'off the centre of its cover',
          );
        }
      }
    }
  });
}
