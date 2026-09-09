import 'package:attune/features/games/presentation/widgets/game_trail_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendered and looked at. The trail's whole job is to show WHICH SIDE
/// moved, so "does it read as mine or theirs at a glance" is not a
/// question code review can answer.
void main() {
  Widget wrap(Widget child, {required Brightness brightness}) => ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            backgroundColor: brightness == Brightness.dark
                ? const Color(0xFF101014)
                : const Color(0xFFF2F2F7),
            body: Center(child: child),
          ),
        ),
      );

  /// Stands in for the bubble the trail now sits in.
  Widget bubbled(Widget child, Color fill, {required bool isMine}) => Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(24),
          ),
          child: child,
        ),
      );

  testWidgets('a trail on each side, dark', (tester) async {
    await tester.pumpWidget(wrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          bubbled(
            const GameTrailLine(
              label: 'Paint Ball',
              isMine: false,
              foregroundColor: Colors.white,
              gameType: 'paint_ball',
            ),
            const Color(0xFF2A2A2E),
            isMine: false,
          ),
          bubbled(
            const GameTrailLine(
              label: 'Paint Ball',
              isMine: true,
              foregroundColor: Colors.white,
              gameType: 'paint_ball',
            ),
            const Color(0xFF2F6D62),
            isMine: true,
          ),
          bubbled(
            const GameTrailLine(
              label: 'Word Hunt',
              isMine: false,
              foregroundColor: Colors.white,
              gameType: 'word_hunt',
            ),
            const Color(0xFF2A2A2E),
            isMine: false,
          ),
        ],
      ),
      brightness: Brightness.dark,
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Column),
      matchesGoldenFile('goldens/game_trail_dark.png'),
    );
  });

  testWidgets('a trail on each side, light', (tester) async {
    await tester.pumpWidget(wrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          bubbled(
            const GameTrailLine(
              label: 'Snakes and Ladders',
              isMine: false,
              foregroundColor: Color(0xFF1A1A1A),
              gameType: 'snakes_and_ladders',
            ),
            const Color(0xFFFFFFFF),
            isMine: false,
          ),
          bubbled(
            const GameTrailLine(
              label: 'Snakes and Ladders',
              isMine: true,
              foregroundColor: Color(0xFF07271F),
              gameType: 'snakes_and_ladders',
            ),
            const Color(0xFF9FE8D8),
            isMine: true,
          ),
        ],
      ),
      brightness: Brightness.light,
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Column),
      matchesGoldenFile('goldens/game_trail_light.png'),
    );
  });
}
