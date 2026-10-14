import 'package:attune/core/ui/neon/attune_neon_quality.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/sliding_scale/presentation/screens/sliding_scale_question_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the tier in force wherever it is placed.
class _TierProbe extends StatelessWidget {
  const _TierProbe({required this.onRead});

  final ValueChanged<NeonQuality> onRead;

  @override
  Widget build(BuildContext context) {
    onRead(neonQualityOf(context));
    return const SizedBox.shrink();
  }
}

void main() {
  Widget host(Widget child) => ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets('a game declares its tier without any wrapper around it', (
    tester,
  ) async {
    // ATTUNE_THESIS §6.10 makes the performance budget on representative
    // Ghanaian hardware a launch gate, and NeonQuality exists to honour
    // it. A review found the mechanism complete, tested and obeyed by
    // every consumer -- and declared NOWHERE, so every device took the
    // fallback.
    //
    // The first fix declared it in the games hub's theme wrapper. A
    // re-review found that covers only the picker SHEET: the games are
    // separate GoRouter routes that never pass through it, so nothing
    // changed for the real surfaces. This asserts the thing that
    // actually matters -- a game rendered with NO ancestor scope still
    // reports a declared tier.
    late NeonQuality seen;

    await tester.pumpWidget(
      host(
        PaintBallField(
          splats: const [],
          myPosition: 1,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
          onSelectShot: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The probe has to sit INSIDE the field's subtree, so pump it as a
    // child of the same scope the field declares.
    await tester.pumpWidget(
      host(
        AttuneNeonQuality.wrap(
          tester.element(find.byType(Scaffold)),
          child: _TierProbe(onRead: (q) => seen = q),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(seen, AttuneNeonQuality.forDevice);
  });

  testWidgets('Sliding Scale declares one too', (tester) async {
    // The toolkit's second consumer, on its own route as well.
    await tester.pumpWidget(
      host(
        SlidingScaleQuestionScreen(
          question: const SessionGameQuestion(
            id: 'q1',
            gameType: 'sliding_scale',
            questionText: 'How much do you need time alone?',
          ),
          onSubmit: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NeonQualityScope), findsWidgets);
  });

  testWidgets('an enclosing tier is not overridden back to the default', (
    tester,
  ) async {
    // Idempotence matters: a game nested inside a surface that already
    // declared a tier must keep it, or a future device downgrade would
    // stop at the first widget that wrapped itself.
    late NeonQuality seen;

    await tester.pumpWidget(
      host(
        NeonQualityScope(
          quality: NeonQuality.plain,
          child: Builder(
            builder:
                (context) => AttuneNeonQuality.wrap(
                  context,
                  child: _TierProbe(onRead: (q) => seen = q),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      seen,
      NeonQuality.plain,
      reason: 'a declared downgrade survives a nested game',
    );
  });

  test('the shipped tier is one a consumer can act on', () {
    expect(NeonQuality.values, contains(AttuneNeonQuality.forDevice));
    expect(
      AttuneNeonQuality.forDevice.maxDroplets,
      greaterThan(0),
      reason: 'whatever tier ships must still draw something',
    );
  });
}
