import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/stories/presentation/widgets/story_progress_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  List<bool>? viewed,
  int current = 1,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StoryProgressBars(
          itemCount: 3,
          currentIndex: current,
          currentProgress: 0.5,
          viewed: viewed,
        ),
      ),
    ),
  );
}

({double width, Color fill}) _segment(WidgetTester tester, int i) {
  final scope = find.byKey(ValueKey('story-progress-segment-$i'));
  final box = tester.widget<FractionallySizedBox>(
    find.descendant(of: scope, matching: find.byType(FractionallySizedBox)),
  );
  final fill = tester.widget<ColoredBox>(
    find.descendant(
      of: find.descendant(
        of: scope,
        matching: find.byType(FractionallySizedBox),
      ),
      matching: find.byType(ColoredBox),
    ),
  );
  return (width: box.widthFactor!, fill: fill.color);
}

void main() {
  testWidgets('the fill stays white in dark mode', (tester) async {
    await _pump(tester, theme: AppTheme.darkTheme);
    expect(_segment(tester, 0).fill, Colors.white);
    expect(_segment(tester, 1).width, 0.5);
  });

  testWidgets('a story already seen ahead of the current one shows faded', (
    tester,
  ) async {
    await _pump(
      tester,
      theme: AppTheme.lightTheme,
      current: 0,
      viewed: const [false, false, true],
    );
    expect(_segment(tester, 1).width, 0.0);
    expect(_segment(tester, 2).width, 1.0);
    expect(_segment(tester, 2).fill, StoryProgressBars.seenColor);
  });
}
