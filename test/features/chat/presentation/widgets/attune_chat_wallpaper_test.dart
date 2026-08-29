import 'package:attune/features/chat/presentation/widgets/attune_chat_wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

void main() {
  Widget buildWallpaper({bool reduceMotion = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: AttuneChatWallpaper(child: Text('Conversation content')),
          ),
        ),
      ),
    );
  }

  testWidgets('shows lottie-only decorative wallpaper patterns', (
    tester,
  ) async {
    await tester.pumpWidget(buildWallpaper());
    await tester.pump();

    expect(find.text('Conversation content'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-wallpaper-lottie-experiment')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('animated-chat-doodles')), findsNothing);
    expect(find.byType(LottieBuilder), findsAtLeastNWidgets(100));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lottie patterns stay anchored with only some frames repeating', (
    tester,
  ) async {
    await tester.pumpWidget(buildWallpaper());

    final motif = find.byKey(const ValueKey('chat-lottie-0'));
    final motifPositionBefore = tester.getTopLeft(motif);
    final lottieBefore = tester.widget<LottieBuilder>(
      find.descendant(of: motif, matching: find.byType(LottieBuilder)),
    );

    await tester.pump(const Duration(milliseconds: 750));

    final motifPositionAfter = tester.getTopLeft(motif);
    final lottieAfter = tester.widget<LottieBuilder>(
      find.descendant(of: motif, matching: find.byType(LottieBuilder)),
    );
    expect(motifPositionAfter, motifPositionBefore);
    expect(lottieBefore.animate, isTrue);
    expect(lottieAfter.repeat, isTrue);

    final lottieAnimations = tester.widgetList<LottieBuilder>(
      find.byType(LottieBuilder),
    );
    final animatedCount =
        lottieAnimations.where((item) => item.animate == true).length;
    final staticCount =
        lottieAnimations.where((item) => item.animate != true).length;
    expect(animatedCount, greaterThan(0));
    expect(staticCount, greaterThan(animatedCount));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lottie patterns use a constant diagonal lattice on a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(buildWallpaper());

    final motifRects =
        List.generate(
          8,
          (index) => tester.getRect(find.byKey(ValueKey('chat-lottie-$index'))),
        ).toList();
    expect(find.byType(LottieBuilder), findsNWidgets(171));
    expect(motifRects.map((rect) => rect.width).toSet(), hasLength(1));

    for (var index = 1; index < motifRects.length; index++) {
      expect(motifRects[index].left - motifRects[index - 1].left, 56);
      expect(motifRects[index].top - motifRects[index - 1].top, -3);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps all patterns visible but frozen when motion is reduced', (
    tester,
  ) async {
    await tester.pumpWidget(buildWallpaper(reduceMotion: true));

    expect(find.text('Conversation content'), findsOneWidget);
    expect(find.byKey(const ValueKey('animated-chat-doodles')), findsNothing);

    final lottieAnimations = tester.widgetList<LottieBuilder>(
      find.byType(LottieBuilder),
    );
    expect(lottieAnimations.length, greaterThanOrEqualTo(100));
    expect(
      lottieAnimations.every((animation) => animation.animate == false),
      isTrue,
    );
    expect(
      lottieAnimations.every((animation) => animation.repeat == false),
      isTrue,
    );
  });
}
