import 'package:attune/features/chat/presentation/widgets/lottie_doodle_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

Widget _wrap(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        disableAnimations: reduceMotion,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 390, height: 844, child: child),
      ),
    );

void main() {
  testWidgets('packs Lottie motifs into a dense field', (tester) async {
    await tester.pumpWidget(_wrap(const LottieDoodleField(color: Colors.green)));
    await tester.pump();

    expect(
      find.byType(LottieBuilder).evaluate().length,
      greaterThanOrEqualTo(30),
      reason: 'the reference is packed, not a handful of motifs',
    );
  });

  testWidgets('caps the field — Lottie is far heavier than an SVG',
      (tester) async {
    // Checked on a LARGE surface, where the packing produces well over
    // the cap. On a phone it yields fewer than 40 anyway, so a
    // phone-sized assertion passes even with the cap removed entirely.
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1400, 2200)),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 1400,
          height: 2200,
          child: LottieDoodleField(color: Colors.green),
        ),
      ),
    ));
    await tester.pump();

    expect(
      find.byType(LottieBuilder).evaluate().length,
      // A LITERAL, not kMaxLottieDoodles: comparing against the constant
      // makes the assertion move with it, so raising the cap to 500 would
      // still pass. The number here is the budget this wallpaper is
      // allowed, independent of what the source claims.
      lessThanOrEqualTo(45),
      reason: 'each Lottie carries its own composition and controller; an '
          'uncapped field is a battery and memory cost behind a chat',
    );
  });

  testWidgets('renders every motif at rest when motion is reduced',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const LottieDoodleField(color: Colors.green), reduceMotion: true),
    );
    await tester.pump();

    expect(find.byType(LottieBuilder), findsWidgets);
  });

  testWidgets('is stable across rebuilds', (tester) async {
    await tester.pumpWidget(_wrap(const LottieDoodleField(color: Colors.green)));
    await tester.pump();
    final first = find.byType(LottieBuilder).evaluate().length;

    await tester.pumpWidget(_wrap(const LottieDoodleField(color: Colors.green)));
    await tester.pump();

    expect(find.byType(LottieBuilder).evaluate().length, first);
  });
}
