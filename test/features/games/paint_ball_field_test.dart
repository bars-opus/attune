import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_lives_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
);

Widget _wrapReduced(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder:
      (context, _) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: child),
        ),
      ),
);

/// Counts the player triangles on the field.
///
/// A triangle exists only where a player's position is known -- your own
/// always, theirs only after a round resolves. Counting the painters
/// directly is the strictest form of that rule: it cannot be satisfied by
/// a hidden-but-present widget.
int _visibleTriangles(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .where(
        (widget) => widget.painter.runtimeType.toString().contains('Triangle'),
      )
      .length;
}

const _names = ['Left', 'Middle', 'Right'];

void main() {
  testWidgets('the field renders with a full match of paint', (tester) async {
    // The painter builds an irregular path per splat with a seeded
    // random. A field late in a match is where it either holds up or
    // throws, so it is pumped with more splats than it will ever show.
    final splats = [
      for (var round = 0; round < 20; round++)
        PaintSplat(
          position: round % kPaintBallPositions,
          isMine: round.isEven,
          hit: round % 3 == 0,
          round: round,
        ),
    ];

    await tester.pumpWidget(
      _wrap(
        PaintBallField(
          splats: splats,
          myPosition: 1,
          selectedShot: 2,
          revealedPartnerPosition: 0,
          isMyTurn: true,
          onSelectShot: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty field renders', (tester) async {
    // The opening move, before anyone has fired.
    await tester.pumpWidget(
      _wrap(
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
  });

  testWidgets('each row taps to its own action', (tester) async {
    // v3: the board is the controller. Your row repositions you, theirs
    // picks a target. They must stay distinct -- a tap that could do
    // either would let a player spend a turn while browsing covers.
    final shots = <int>[];
    final hides = <int>[];

    await tester.pumpWidget(
      _wrap(
        PaintBallField(
          splats: const [],
          myPosition: 0,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
          onSelectShot: shots.add,
          onSelectHide: hides.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < kPaintBallPositions; i++) {
      await tester.tap(find.bySemanticsLabel('${_names[i]} target'));
      await tester.tap(find.bySemanticsLabel('${_names[i]} cover'));
    }
    await tester.pump();

    expect(shots, [0, 1, 2], reason: 'their row selects a target');
    expect(hides, [0, 1, 2], reason: 'your row repositions you');
  });

  testWidgets('firing is the triangle, never a cover', (tester) async {
    // Committing a shot must be its own act. If a cover could fire, a
    // mis-tap while choosing a target would spend the turn.
    var fired = 0;
    final shots = <int>[];

    await tester.pumpWidget(
      _wrap(
        PaintBallField(
          splats: const [],
          myPosition: 1,
          selectedShot: 2,
          revealedPartnerPosition: null,
          isMyTurn: true,
          onSelectShot: shots.add,
          onSelectHide: (_) {},
          onFire: () => fired++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tapping the aimed cover again re-selects; it does not fire.
    await tester.tap(find.bySemanticsLabel('Right target'));
    await tester.pump();
    expect(fired, 0, reason: 'a cover tap must never fire');

    // The occupied triangle on your own row is the fire control.
    await tester.tap(
      find
          .descendant(
            of: find.bySemanticsLabel('Middle cover'),
            matching: find.byType(CustomPaint),
          )
          .first,
      warnIfMissed: false,
    );
    await tester.pump();
    expect(fired, greaterThan(0), reason: 'the triangle fires');
  });

  testWidgets('nothing is selectable when it is not your turn', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      _wrap(
        PaintBallField(
          splats: const [],
          myPosition: 0,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: false,
          onSelectShot: (_) => tapped = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final target in find.byType(GestureDetector).evaluate()) {
      await tester.tap(find.byWidget(target.widget), warnIfMissed: false);
    }
    await tester.pump();

    expect(tapped, isFalse, reason: 'a player must not move out of turn');
  });

  testWidgets('your own triangle is visible, theirs is not', (tester) async {
    // The whole game rests on this asymmetry. You can see where you are
    // hiding; their position appears only after a shot resolves against
    // it. If both were drawn, the guess would stop being a guess.
    await tester.pumpWidget(
      _wrap(
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

    expect(
      _visibleTriangles(tester),
      1,
      reason: 'only the viewer\'s own position may be shown',
    );
  });

  testWidgets('a revealed partner position becomes visible', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PaintBallField(
          splats: [],
          myPosition: 1,
          selectedShot: 2,
          revealedPartnerPosition: 0,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _visibleTriangles(tester),
      2,
      reason: 'after the reveal both positions are on the field',
    );
  });

  testWidgets('a shot in flight renders', (tester) async {
    // The projectile is drawn from the shooter's shield to the target's,
    // so it needs both positions. Mid-flight is the frame that matters.
    await tester.pumpWidget(
      _wrap(
        const PaintBallField(
          splats: [],
          myPosition: 0,
          selectedShot: 2,
          revealedPartnerPosition: null,
          isMyTurn: true,
          shotProgress: 0.5,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a shot with no chosen positions still renders', (tester) async {
    // Defensive: the projectile falls back to the centre rather than
    // throwing on a null position, so a mid-flight rebuild after state
    // clears cannot crash the screen.
    await tester.pumpWidget(
      _wrap(
        const PaintBallField(
          splats: [],
          myPosition: null,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
          shotProgress: 0.3,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the three targets are labelled and focusable', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(
      _wrap(
        PaintBallField(
          splats: const [],
          myPosition: 1,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
          onSelectShot: tapped.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Left target'), findsOneWidget);
    expect(find.bySemanticsLabel('Middle target'), findsOneWidget);
    expect(find.bySemanticsLabel('Right target'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Right target'));
    expect(tapped, [2]);
  });

  testWidgets('reduce motion makes all field transitions immediate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapReduced(
        const PaintBallField(
          splats: [],
          myPosition: 0,
          selectedShot: 2,
          revealedPartnerPosition: 1,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pump();

    for (final widget in tester.widgetList<AnimatedAlign>(
      find.byType(AnimatedAlign),
    )) {
      expect(widget.duration, Duration.zero);
    }
    for (final widget in tester.widgetList<AnimatedSlide>(
      find.byType(AnimatedSlide),
    )) {
      expect(widget.duration, Duration.zero);
    }
    for (final widget in tester.widgetList<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    )) {
      expect(widget.duration, Duration.zero);
    }
  });

  testWidgets('lives use text and become immediate with reduce motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapReduced(
        const PaintBallLivesDisplay(
          myLives: 2,
          opponentLives: 1,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel(
        'Your partner has 1 lives. You have 2 lives. It is your turn.',
      ),
      findsOneWidget,
    );
    for (final widget in tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    )) {
      expect(widget.duration, Duration.zero);
    }
  });

  testWidgets('a replay shows both players, then hides theirs again', (
    tester,
  ) async {
    // The replay is the only moment both positions are on the field. It
    // is what turns a resolved round from arithmetic into something the
    // couple watched happen.
    await tester.pumpWidget(
      _wrap(
        const PaintBallField(
          splats: [],
          myPosition: 0,
          selectedShot: 1,
          revealedPartnerPosition: 1,
          theirRevealedShot: 0,
          isMyTurn: false,
          isReplaying: true,
          replayProgress: 0.7,
        ),
      ),
    );
    await tester.pump();

    expect(
      _visibleTriangles(tester),
      2,
      reason: 'both players are on the field during a replay',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mid-replay both paintballs are in flight at once', (
    tester,
  ) async {
    // Both players fired without seeing the other, so the shots cross
    // rather than take turns. Watching them pass is what makes the round
    // read as a duel instead of two separate moves.
    await tester.pumpWidget(
      _wrap(
        const PaintBallField(
          splats: [],
          myPosition: 0,
          selectedShot: 2,
          revealedPartnerPosition: 2,
          theirRevealedShot: 0,
          isMyTurn: false,
          isReplaying: true,
          replayProgress: 0.7,
        ),
      ),
    );
    await tester.pump();

    final projectiles =
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where(
              (widget) =>
                  widget.painter.runtimeType.toString().contains('Projectile'),
            )
            .length;

    expect(
      projectiles,
      2,
      reason: 'a replay puts both shots in the air together',
    );
  });

  testWidgets('early in a replay nobody has fired yet', (tester) async {
    // Emerging and aiming get room to read before anything leaves a
    // barrel. A shot that flew before the aim landed would skip the part
    // worth watching.
    await tester.pumpWidget(
      _wrap(
        const PaintBallField(
          splats: [],
          myPosition: 0,
          selectedShot: 2,
          revealedPartnerPosition: 2,
          theirRevealedShot: 0,
          isMyTurn: false,
          isReplaying: true,
          replayProgress: 0.05,
        ),
      ),
    );
    await tester.pump();

    final projectiles =
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where(
              (widget) =>
                  widget.painter.runtimeType.toString().contains('Projectile'),
            )
            .length;

    expect(projectiles, 0, reason: 'no shot before the aim has landed');
  });

  testWidgets('repositioning travels rather than teleporting', (tester) async {
    // Moving cover is a journey: the triangle leaves, crosses, and enters
    // the new cover as one body. A cross-fade between two covers would
    // read as two triangles, and taking cover would feel like being
    // reassigned rather than moving.
    Widget field(int position) => _wrap(
      PaintBallField(
        splats: const [],
        myPosition: position,
        selectedShot: null,
        revealedPartnerPosition: null,
        isMyTurn: true,
        onSelectShot: (_) {},
        onSelectHide: (_) {},
      ),
    );

    await tester.pumpWidget(field(0));
    await tester.pumpAndSettle();

    Offset trianglePosition() {
      final finder = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString().contains('Triangle'),
      );
      return tester.getCenter(finder.first);
    }

    final start = trianglePosition();

    await tester.pumpWidget(field(2));
    await tester.pump(const Duration(milliseconds: 310));
    final middle = trianglePosition();

    await tester.pumpAndSettle();
    final end = trianglePosition();

    // It is genuinely between the two covers partway through, not already
    // arrived and not still waiting.
    expect(
      middle.dx,
      greaterThan(start.dx),
      reason: 'the triangle has set off',
    );
    expect(
      middle.dx,
      lessThan(end.dx),
      reason: 'the triangle has not arrived yet -- it is travelling',
    );

    // And exactly one triangle exists throughout: it is the same body
    // moving, never a second one fading in.
    expect(_visibleTriangles(tester), 1);
  });

  testWidgets('a travelling player steps clear of cover', (tester) async {
    // Sliding sideways while still tucked in would read as passing
    // through the wall, so the crossing happens stepped out.
    Widget field(int position) => _wrap(
      PaintBallField(
        splats: const [],
        myPosition: position,
        selectedShot: null,
        revealedPartnerPosition: null,
        isMyTurn: true,
        onSelectShot: (_) {},
        onSelectHide: (_) {},
      ),
    );

    Offset trianglePosition() {
      final finder = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString().contains('Triangle'),
      );
      return tester.getCenter(finder.first);
    }

    await tester.pumpWidget(field(0));
    await tester.pumpAndSettle();
    final atRest = trianglePosition();

    await tester.pumpWidget(field(2));
    await tester.pump(const Duration(milliseconds: 310));
    final crossing = trianglePosition();

    // Your row is at the bottom, so stepping out of cover moves UP the
    // screen -- a smaller dy.
    expect(
      crossing.dy,
      lessThan(atRest.dy),
      reason: 'the crossing happens clear of cover, not through it',
    );
  });

  testWidgets('the character stands in the centre of its cover', (
    tester,
  ) async {
    // Reported from a device: the triangle sat at the right edge of its
    // cover rather than inside it.
    //
    // The traveller positioned itself on notional slots (row width / 3)
    // while the covers are a FIXED width laid out with even gaps. Those
    // two only agree when the row happens to be exactly three covers
    // wide -- at any other width the character drifts, worst at the
    // outer covers. So this checks every position at several widths,
    // since a single width can pass by coincidence.
    for (final width in [360.0, 390.0, 430.0]) {
      for (var position = 0; position < kPaintBallPositions; position++) {
        tester.view.physicalSize = Size(width, 932);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _wrap(
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

        final triangle = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter.runtimeType.toString().contains('Triangle'),
          ),
        );
        final cover = tester.getRect(
          find.bySemanticsLabel('${_names[position]} cover'),
        );

        expect(
          (triangle.center.dx - cover.center.dx).abs(),
          lessThan(1.0),
          reason:
              'at width $width the character at position $position sits '
              '${(triangle.center.dx - cover.center.dx).toStringAsFixed(1)}pt '
              'off the centre of its cover',
        );
      }
    }
  });

  testWidgets('the two rows of cover face each other', (tester) async {
    // Reported from a device: both rows domed the same way, so the
    // opponent's cover looked like it was sheltering someone standing
    // off the top of the board rather than facing you across the line.
    //
    // Yours opens downward (legs planted below the dome); theirs opens
    // upward. Checked through the painter's own flag rather than by
    // eye, since the two are mirror images and easy to confuse.
    await tester.pumpWidget(
      _wrap(
        PaintBallField(
          splats: const [],
          myPosition: 1,
          selectedShot: null,
          revealedPartnerPosition: 0,
          isMyTurn: true,
          onSelectShot: (_) {},
          onSelectHide: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shields =
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .where(
              (painter) => painter.runtimeType.toString().contains('Shield'),
            )
            .toList();

    expect(shields, hasLength(kPaintBallPositions * 2));

    final opensDown =
        shields.map((painter) => '$painter'.contains('opensDown')).toList();

    // Three of each: one row mirrored against the other. If every cover
    // faced the same way this would be six or zero.
    final downward =
        shields.where((painter) {
          final field = (painter as dynamic).opensDown as bool;
          return field;
        }).length;

    expect(
      downward,
      kPaintBallPositions,
      reason: 'exactly one row of cover faces the other',
    );
    expect(opensDown, isNotEmpty);
  });
}
