import 'package:attune/features/chat/presentation/widgets/doodle_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

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
  testWidgets('renders a dense field, not a handful of motifs',
      (tester) async {
    await tester.pumpWidget(_wrap(const DoodleField(color: Colors.green)));
    await tester.pump();

    final count = find.byType(SvgPicture).evaluate().length;
    expect(
      count,
      greaterThanOrEqualTo(40),
      reason: 'the reference is a packed field; six motifs cannot read '
          'like it at any scale',
    );
  });

  testWidgets('every doodle still renders when motion is reduced',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const DoodleField(color: Colors.green), reduceMotion: true),
    );
    await tester.pump();

    // Reduce-motion removes the movement, never the wallpaper.
    expect(find.byType(SvgPicture), findsWidgets);
    expect(find.byType(AnimatedBuilder), findsNothing);
  });

  testWidgets('animated doodles are a minority of the field', (tester) async {
    await tester.pumpWidget(_wrap(const DoodleField(color: Colors.green)));
    await tester.pump();

    final total = find.byType(SvgPicture).evaluate().length;
    final animated = find.byType(AnimatedBuilder).evaluate().length;

    expect(animated, greaterThan(0));
    expect(
      animated,
      lessThan(total ~/ 2),
      reason: 'a mostly-animated wallpaper competes with the conversation',
    );
  });

  testWidgets('the field is stable across rebuilds', (tester) async {
    await tester.pumpWidget(_wrap(const DoodleField(color: Colors.green)));
    await tester.pump();
    final first = find.byType(SvgPicture).evaluate().length;

    await tester.pumpWidget(_wrap(const DoodleField(color: Colors.green)));
    await tester.pump();

    expect(
      find.byType(SvgPicture).evaluate().length,
      first,
      reason: 'the wallpaper must not reshuffle under the user',
    );
  });
}
