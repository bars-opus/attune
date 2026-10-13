import 'package:attune/core/ui/motion/animated_keyed_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _row(String id) => SizedBox(key: ValueKey(id), height: 40, child: Text(id));

Widget _app(List<String> ids, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: AnimatedKeyedColumn(children: [for (final id in ids) _row(id)])),
      ),
    );

double _y(WidgetTester tester, String id) => tester.getTopLeft(find.text(id)).dy;

void main() {
  testWidgets('the first build shows everything at once, no entrance', (tester) async {
    await tester.pumpWidget(_app(['a', 'b']));
    expect(tester.getSize(find.byKey(const ValueKey('b'))).height, 40);
    expect(_y(tester, 'b') - _y(tester, 'a'), 40);
  });

  testWidgets('an added item grows open and fades in, pushing the next one down smoothly', (tester) async {
    await tester.pumpWidget(_app(['a', 'c']));
    final cBefore = _y(tester, 'c');
    await tester.pumpWidget(_app(['a', 'b', 'c']));
    await tester.pump(const Duration(milliseconds: 100));
    final cMid = _y(tester, 'c');
    expect(cMid, greaterThan(cBefore), reason: 'c is moving down');
    expect(cMid, lessThan(cBefore + 40), reason: 'but not there yet');
    final fade = tester.widget<FadeTransition>(
        find.ancestor(of: find.text('b'), matching: find.byType(FadeTransition)).first);
    expect(fade.opacity.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(_y(tester, 'c'), cBefore + 40);
  });

  testWidgets('a removed item stays while it fades and closes, then is gone', (tester) async {
    await tester.pumpWidget(_app(['a', 'b', 'c']));
    final cBefore = _y(tester, 'c');
    await tester.pumpWidget(_app(['a', 'c']));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('b'), findsOneWidget, reason: 'still leaving');
    expect(_y(tester, 'c'), inExclusiveRange(cBefore - 40, cBefore));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsNothing);
    expect(_y(tester, 'c'), cBefore - 40);
  });

  testWidgets('reordered items glide from where they were to where they now are', (tester) async {
    await tester.pumpWidget(_app(['a', 'b', 'c']));
    final aStart = _y(tester, 'a');
    final cStart = _y(tester, 'c');
    await tester.pumpWidget(_app(['c', 'b', 'a']));
    await tester.pump(); // first frame of the move: still where they were, no jump
    expect(_y(tester, 'a'), moreOrLessEquals(aStart));
    expect(_y(tester, 'c'), moreOrLessEquals(cStart));
    await tester.pump(const Duration(milliseconds: 120));
    expect(_y(tester, 'a'), inExclusiveRange(aStart, cStart));
    expect(_y(tester, 'c'), inExclusiveRange(aStart, cStart));
    await tester.pumpAndSettle();
    expect(_y(tester, 'a'), moreOrLessEquals(cStart));
    expect(_y(tester, 'c'), moreOrLessEquals(aStart));
  });

  testWidgets('with reduce motion, changes land at once', (tester) async {
    await tester.pumpWidget(_app(['a', 'b', 'c'], reduceMotion: true));
    final aStart = _y(tester, 'a');
    final cStart = _y(tester, 'c');
    await tester.pumpWidget(_app(['c', 'a'], reduceMotion: true));
    await tester.pump();
    expect(find.text('b'), findsNothing);
    expect(_y(tester, 'c'), moreOrLessEquals(aStart));
    expect(_y(tester, 'a'), moreOrLessEquals(aStart + 40));
    expect(cStart, isNot(aStart));
  });

  testWidgets('an item removed and put back (Undo) comes back in place', (tester) async {
    await tester.pumpWidget(_app(['a', 'b', 'c']));
    final bStart = _y(tester, 'b');
    await tester.pumpWidget(_app(['a', 'c']));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(_app(['a', 'b', 'c']));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsOneWidget);
    expect(_y(tester, 'b'), moreOrLessEquals(bStart));
  });
}
