import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendered and LOOKED AT, not merely diffed.
///
/// The same rule the Word Hunt goldens carry, and for the same reason:
/// every visual bug in the Arcade so far -- arches shaped like domes, a
/// figure sitting on the edge of its cover, a divider sized by its
/// sibling and so drawing nothing at all -- was found by rendering a
/// golden and opening the PNG. Code that reads correctly draws wrongly
/// often enough that this is the only honest check.
///
/// These are the Stage 2 checkpoint frames. They answer one question the
/// tests cannot: does cover-as-darkness actually work?
void main() {
  Widget host(Widget child, {NeonQuality quality = NeonQuality.rich}) =>
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (context, _) => MaterialApp(
              home: Scaffold(
                backgroundColor: const Color(0xFF07070A),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: NeonQualityScope(quality: quality, child: child),
                  ),
                ),
              ),
            ),
      );

  testWidgets('at rest, nobody aiming', (tester) async {
    // The still frame. §2.5 says the field at rest IS a still image, so
    // this is what a couple sees most of the time.
    await tester.pumpWidget(
      host(
        const PaintBallField(
          splats: [],
          myPosition: 1,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
          partnerName: 'Ama',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PaintBallField),
      matchesGoldenFile('goldens/paint_ball_field_rest.png'),
    );
  });

  testWidgets('aiming at their middle cover', (tester) async {
    // THE question for the checkpoint. With no Fire button the aimed bay
    // is the only confirmation that a target is chosen, so if this frame
    // does not read as obviously committed, §2.3 needs rethinking.
    await tester.pumpWidget(
      host(
        PaintBallField(
          splats: const [],
          myPosition: 0,
          selectedShot: 1,
          revealedPartnerPosition: null,
          isMyTurn: true,
          partnerName: 'Ama',
          onSelectShot: (_) {},
          onSelectHide: (_) {},
          onFire: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PaintBallField),
      matchesGoldenFile('goldens/paint_ball_field_aimed.png'),
    );
  });

  testWidgets('mid-replay, both shots in the air', (tester) async {
    // The hero moment, such as it is before Stage 4 rebuilds it.
    await tester.pumpWidget(
      host(
        const PaintBallField(
          splats: [
            PaintSplat(position: 1, isMine: true, hit: true, round: 1),
          ],
          myPosition: 0,
          selectedShot: 2,
          revealedPartnerPosition: 2,
          theirRevealedShot: 0,
          isMyTurn: false,
          isReplaying: true,
          replayProgress: 0.7,
          partnerName: 'Ama',
          theirStreak: 3,
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(PaintBallField),
      matchesGoldenFile('goldens/paint_ball_field_replay.png'),
    );
  });

  testWidgets('a hit, with paint on the board', (tester) async {
    await tester.pumpWidget(
      host(
        const PaintBallField(
          splats: [
            PaintSplat(position: 2, isMine: true, hit: true, round: 4),
            PaintSplat(position: 0, isMine: false, hit: false, round: 4),
          ],
          myPosition: 1,
          selectedShot: 2,
          revealedPartnerPosition: 2,
          isMyTurn: false,
          partnerName: 'Ama',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PaintBallField),
      matchesGoldenFile('goldens/paint_ball_field_hit.png'),
    );
  });

  testWidgets('the plain tier, for a low-end device', (tester) async {
    // ATTUNE_THESIS §6.10 makes this a launch gate, so the degraded
    // frame has to be LOOKED at too. It must still read as a playable
    // board, not as a broken one.
    await tester.pumpWidget(
      host(
        const PaintBallField(
          splats: [
            PaintSplat(position: 1, isMine: true, hit: true, round: 1),
          ],
          myPosition: 1,
          selectedShot: 0,
          revealedPartnerPosition: null,
          isMyTurn: true,
          partnerName: 'Ama',
        ),
        quality: NeonQuality.plain,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PaintBallField),
      matchesGoldenFile('goldens/paint_ball_field_plain.png'),
    );
  });

  testWidgets('under reduce motion', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (context, _) => MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: Scaffold(
                  backgroundColor: const Color(0xFF07070A),
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: const PaintBallField(
                        splats: [],
                        myPosition: 2,
                        selectedShot: 1,
                        revealedPartnerPosition: 1,
                        isMyTurn: true,
                        partnerName: 'Ama',
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(PaintBallField),
      matchesGoldenFile('goldens/paint_ball_field_reduce_motion.png'),
    );
  });
}
