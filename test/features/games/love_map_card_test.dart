import 'package:attune/features/games/love_map/presentation/widgets/love_map_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows coverage, never an accuracy figure', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LoveMapCard(answered: 34, total: 60, newCount: 3, onTap: () {}),
      ),
    ));

    expect(find.text('You know 34 of 60 answers'), findsOneWidget);
    // §11.1: coverage is mutual progress. An accuracy total would be a
    // score, which Love Map deliberately does not keep.
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('correct'), findsNothing);
  });

  testWidgets('shows the new-question badge only when there are some',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LoveMapCard(answered: 60, total: 60, newCount: 0, onTap: () {}),
      ),
    ));
    expect(find.textContaining('new'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LoveMapCard(answered: 10, total: 60, newCount: 3, onTap: () {}),
      ),
    ));
    expect(find.text('3 new'), findsOneWidget);
  });

  testWidgets('a zero total does not divide by zero', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LoveMapCard(answered: 0, total: 0, newCount: 0, onTap: () {}),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the card fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LoveMapCard(
            answered: 1, total: 60, newCount: 0, onTap: () => tapped = true),
      ),
    ));
    await tester.tap(find.byType(LoveMapCard));
    expect(tapped, isTrue);
  });
}
