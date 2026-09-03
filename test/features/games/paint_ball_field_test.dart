import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
);

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
}
