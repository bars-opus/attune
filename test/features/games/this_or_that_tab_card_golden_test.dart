import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_tab_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendered and LOOKED AT, not merely diffed.
///
/// Paint Ball's lesson, learned the expensive way: it passed every test
/// and still did not read as something worth opening. These frames exist
/// to be opened.
void main() {
  /// Pin the view to a phone.
  ///
  /// The golden surface defaults to 800x600 LANDSCAPE while the design
  /// size is 375x812 portrait. Judging a card's proportions against that
  /// is judging a different card -- the mistake that cost three figure
  /// redesigns on the Paint Ball work before it was caught.
  void onPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      builder:
          (context, _) => MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              backgroundColor:
                  brightness == Brightness.light
                      ? const Color(0xFFF7F5F1)
                      : const Color(0xFF111214),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: child,
                ),
              ),
            ),
          ),
    );
  }

  ThisOrThatTabCard card(ThisOrThatTab active) => ThisOrThatTabCard(
    questionText: 'Night in or night out?',
    optionA: 'Night in, nowhere to be',
    optionB: 'Night out, somewhere loud',
    emojiA: '🛋️',
    emojiB: '🎶',
    active: active,
    onSelect: (_) {},
  );

  testWidgets('the question, before a choice', (tester) async {
    onPhone(tester);
    await tester.pumpWidget(host(card(ThisOrThatTab.question)));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ThisOrThatTabCard),
      matchesGoldenFile('goldens/this_or_that_question.png'),
    );
  });

  testWidgets('THIS pulled forward', (tester) async {
    onPhone(tester);
    await tester.pumpWidget(host(card(ThisOrThatTab.thisOption)));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ThisOrThatTabCard),
      matchesGoldenFile('goldens/this_or_that_this.png'),
    );
  });

  testWidgets('THAT pulled forward', (tester) async {
    onPhone(tester);
    await tester.pumpWidget(host(card(ThisOrThatTab.thatOption)));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ThisOrThatTabCard),
      matchesGoldenFile('goldens/this_or_that_that.png'),
    );
  });

  testWidgets('in dark mode', (tester) async {
    onPhone(tester);
    await tester.pumpWidget(
      host(card(ThisOrThatTab.thisOption), brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ThisOrThatTabCard),
      matchesGoldenFile('goldens/this_or_that_dark.png'),
    );
  });
}
