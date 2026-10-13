import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:attune/core/widgets/media/stacked_media_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/media_counter.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('a stack shows a counter, swipes to the next card, and opens the front one', (tester) async {
    int? opened;
    final fronts = <int>[];
    await tester.pumpWidget(_app(StackedMediaCards(
      itemCount: 3,
      itemKey: (i) => 'p$i',
      itemBuilder: (_, i) => ColoredBox(color: Colors.teal, child: Text('card $i')),
      borderColor: Colors.white,
      backColor: Colors.grey,
      onTap: (i) => opened = i,
      onFrontChanged: fronts.add,
    )));
    expect(mediaCounter('1 / 3'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-230, 0));
    await tester.pumpAndSettle();
    expect(mediaCounter('2 / 3'), findsOneWidget);
    expect(fronts, [1]);
    await tester.tap(find.byType(PageView));
    expect(opened, 1);
  });

  testWidgets('a single card has no counter and no cards behind it', (tester) async {
    await tester.pumpWidget(_app(StackedMediaCards(
      itemCount: 1,
      itemKey: (i) => 'p$i',
      itemBuilder: (_, i) => const SizedBox.expand(),
      borderColor: Colors.white,
      backColor: Colors.grey,
    )));
    expect(mediaCounter(), findsNothing);
    expect(
        find.byWidgetPredicate((w) => '${w.key}'.contains('stacked-media-back-card')), findsNothing);
  });

  testWidgets('the front card stays put when an item is added behind it', (tester) async {
    Widget stack(List<String> ids) => _app(StackedMediaCards(
          itemCount: ids.length,
          itemKey: (i) => ids[i],
          itemBuilder: (_, i) => Text(ids[i]),
          borderColor: Colors.white,
          backColor: Colors.grey,
        ));
    await tester.pumpWidget(stack(['a', 'b']));
    await tester.drag(find.byType(PageView), const Offset(-230, 0));
    await tester.pumpAndSettle();
    expect(mediaCounter('2 / 2'), findsOneWidget);
    await tester.pumpWidget(stack(['x', 'a', 'b'])); // a new item at the front of the list
    await tester.pumpAndSettle();
    expect(mediaCounter('3 / 3'), findsOneWidget, reason: 'still showing b');
  });

  testWidgets('a stack can grow from one card to four as photos arrive (cards appear behind it)', (tester) async {
    Widget stack(int n) => _app(StackedMediaCards(
          itemCount: n,
          itemKey: (i) => 'p$i',
          itemBuilder: (_, i) => Text('p$i'),
          borderColor: Colors.white,
          backColor: Colors.grey,
        ));
    for (var n = 1; n <= 4; n++) {
      await tester.pumpWidget(stack(n));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$n cards');
    }
    expect(mediaCounter('1 / 4'), findsOneWidget);
  });

  Finder backCards() => find.byWidgetPredicate((w) => '${w.key}'.contains('stacked-media-back-card'));

  testWidgets('peekBehind: the next photos show on the cards beneath the front one', (tester) async {
    await tester.pumpWidget(_app(StackedMediaCards(
      itemCount: 3,
      itemKey: (i) => 'p$i',
      itemBuilder: (_, i) => Text('card $i'),
      borderColor: Colors.white,
      backColor: Colors.grey,
      peekBehind: true,
    )));
    final front = tester.getTopLeft(find.text('card 0'));
    final first = tester.getTopLeft(find.text('card 1'));
    final second = tester.getTopLeft(find.text('card 2'));
    expect(first.dx, greaterThan(front.dx), reason: 'card 1 peeks out beneath');
    expect(second.dx, greaterThan(first.dx), reason: 'card 2 beneath that');
    await tester.drag(find.byType(StackedMediaCards), const Offset(-230, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('card 0')).dx, greaterThan(tester.getTopLeft(find.text('card 2')).dx),
        reason: 'wraps round: card 0 is now at the bottom, so the cards beneath are never blank');
  });

  testWidgets('without peekBehind the cards beneath stay plain, as chat albums are', (tester) async {
    await tester.pumpWidget(_app(StackedMediaCards(
      itemCount: 3,
      itemKey: (i) => 'p$i',
      itemBuilder: (_, i) => Text('card $i'),
      borderColor: Colors.white,
      backColor: Colors.grey,
    )));
    expect(find.descendant(of: backCards(), matching: find.byType(Text)), findsNothing);
  });

  Widget deck({List<int>? fronts, void Function(int)? onTap}) => _app(StackedMediaCards(
        itemCount: 3,
        itemKey: (i) => 'p$i',
        itemBuilder: (_, i) => Text('card $i'),
        borderColor: Colors.white,
        backColor: Colors.grey,
        peekBehind: true,
        onFrontChanged: fronts?.add,
        onTap: onTap,
      ));

  testWidgets('deck: a swipe left deals the front photo off and the one beneath comes forward', (tester) async {
    final fronts = <int>[];
    int? opened;
    await tester.pumpWidget(deck(fronts: fronts, onTap: (i) => opened = i));
    expect(find.byType(PageView), findsNothing, reason: 'a deck, not sliding pages');
    final frontX = tester.getTopLeft(find.text('card 0')).dx;
    final beneathX = tester.getTopLeft(find.text('card 1')).dx;

    final gesture = await tester.startGesture(tester.getCenter(find.byType(StackedMediaCards)));
    await gesture.moveBy(const Offset(-40, 0)); // settles tap vs drag
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    final midX = tester.getTopLeft(find.text('card 1')).dx;
    expect(midX, lessThan(beneathX), reason: 'the photo beneath moves up as the front one is pulled away');
    expect(midX, greaterThan(frontX - 0.01));
    expect(tester.getTopLeft(find.text('card 0')).dx, lessThan(frontX), reason: 'the front photo follows the finger');
    await gesture.up();
    await tester.pumpAndSettle();

    expect(mediaCounter('2 / 3'), findsOneWidget);
    expect(fronts, [1]);
    expect(tester.getTopLeft(find.text('card 1')).dx, moreOrLessEquals(frontX), reason: 'now in front');
    await tester.tap(find.byType(StackedMediaCards));
    expect(opened, 1);
  });

  testWidgets('deck: a swipe right brings the previous photo back on top, wrapping round', (tester) async {
    await tester.pumpWidget(deck());
    final frontX = tester.getTopLeft(find.text('card 0')).dx;
    final gesture = await tester.startGesture(tester.getCenter(find.byType(StackedMediaCards)));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('card 2')).dx, lessThan(frontX), reason: 'the last photo comes in from the side');
    expect(tester.getTopLeft(find.text('card 0')).dx, greaterThan(frontX), reason: 'the front one drops back');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(mediaCounter('3 / 3'), findsOneWidget);
    expect(tester.getTopLeft(find.text('card 2')).dx, moreOrLessEquals(frontX));
  });

  testWidgets('deck: a short drag springs back', (tester) async {
    await tester.pumpWidget(deck());
    final frontX = tester.getTopLeft(find.text('card 0')).dx;
    final gesture = await tester.startGesture(tester.getCenter(find.byType(StackedMediaCards)));
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(mediaCounter('1 / 3'), findsOneWidget);
    expect(tester.getTopLeft(find.text('card 0')).dx, moreOrLessEquals(frontX));
  });

  testWidgets('deck: with two photos, swiping either way never shows the same photo twice', (tester) async {
    await tester.pumpWidget(_app(StackedMediaCards(
      itemCount: 2,
      itemKey: (i) => 'p$i',
      itemBuilder: (_, i) => Text('card $i'),
      borderColor: Colors.white,
      backColor: Colors.grey,
      peekBehind: true,
    )));
    for (final dx in [-60.0, 60.0]) {
      final gesture = await tester.startGesture(tester.getCenter(find.byType(StackedMediaCards)));
      await gesture.moveBy(Offset(dx / 2, 0));
      await gesture.moveBy(Offset(dx / 2, 0));
      await tester.pump();
      expect(find.text('card 1'), findsOneWidget, reason: 'drag $dx');
      expect(tester.takeException(), isNull);
      await gesture.up();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('deck: the counter number rolls (AnimatedRollingCounter) rather than the chip popping', (tester) async {
    await tester.pumpWidget(deck());
    expect(mediaCounter('1 / 3'), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    await tester.drag(find.byType(StackedMediaCards), const Offset(-230, 0));
    await tester.pumpAndSettle();
    expect(mediaCounter('2 / 3'), findsOneWidget);
  });

  testWidgets('deck: a released swipe settles smoothly and unhurried, not in a snap', (tester) async {
    final fronts = <int>[];
    await tester.pumpWidget(deck(fronts: fronts));
    final frontX = tester.getTopLeft(find.text('card 0')).dx;
    final gesture = await tester.startGesture(tester.getCenter(find.byType(StackedMediaCards)));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(); // the settle starts on this frame
    await tester.pump(const Duration(milliseconds: 200));
    expect(fronts, isEmpty, reason: 'still gliding 200 ms after release, not snapped');
    await tester.pumpAndSettle();
    expect(fronts, [1]);
    expect(tester.getTopLeft(find.text('card 1')).dx, moreOrLessEquals(frontX));
  });
}
