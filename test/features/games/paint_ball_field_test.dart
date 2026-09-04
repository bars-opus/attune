import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
);

/// Counts the player triangles that are actually visible.
///
/// Shields and triangles both animate their opacity, so counting every
/// AnimatedOpacity would conflate the two. This walks to the triangle
/// painters specifically -- the thing that reveals where somebody is
/// standing, which is the secret the whole game rests on.
int _visibleTriangles(WidgetTester tester) {
  var count = 0;
  for (final element in find.byType(AnimatedOpacity).evaluate()) {
    final widget = element.widget as AnimatedOpacity;
    if (widget.opacity <= 0) continue;
    final hasTriangle = find
        .descendant(
          of: find.byWidget(widget),
          matching: find.byType(CustomPaint),
        )
        .evaluate()
        .any((e) {
          final painter = (e.widget as CustomPaint).painter;
          return painter.runtimeType.toString().contains('Triangle');
        });
    if (hasTriangle) count++;
  }
  return count;
}

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

  testWidgets('only the opponent row is tappable', (tester) async {
    // You choose where to SHOOT on their side. Tapping your own cover
    // must not fire -- your hiding place is picked in its own step, and
    // conflating the two would let a tap on your own row spend a turn.
    final tapped = <int>[];

    await tester.pumpWidget(
      _wrap(
        PaintBallField(
          splats: const [],
          myPosition: null,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
          onSelectShot: tapped.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final targets = find.byType(GestureDetector);
    expect(targets, findsWidgets);

    // Six cover nodes exist; only the three on the opponent's row report.
    for (var i = 0; i < targets.evaluate().length; i++) {
      await tester.tap(targets.at(i), warnIfMissed: false);
    }
    await tester.pump();

    expect(
      tapped.length,
      kPaintBallPositions,
      reason: 'only the opponent row may be selected',
    );
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
}
