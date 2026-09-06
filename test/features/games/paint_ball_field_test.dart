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
}
