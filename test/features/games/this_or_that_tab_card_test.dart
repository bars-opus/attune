import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_tab_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required ThisOrThatTab active,
    ValueChanged<ThisOrThatTab>? onSelect,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: ThisOrThatTabCard(
          questionText: 'Night in or night out?',
          optionA: 'Night in, nowhere to be',
          optionB: 'Night out, somewhere loud',
          emojiA: '🛋️',
          emojiB: '🎶',
          active: active,
          onSelect: onSelect,
        ),
      ),
    ),
  );

  testWidgets('the question shows before a choice, and no answer does', (
    tester,
  ) async {
    await tester.pumpWidget(host(active: ThisOrThatTab.question));
    await tester.pumpAndSettle();

    expect(find.text('Night in or night out?'), findsOneWidget);
    expect(find.text('Night in, nowhere to be'), findsNothing);
    expect(find.text('Night out, somewhere loud'), findsNothing);
  });

  testWidgets('choosing THIS shows option A and keeps the question', (
    tester,
  ) async {
    // The question stays, smaller. Removing it would leave the answer
    // with nothing to be an answer TO, and a partner glancing over
    // should still see what was asked.
    await tester.pumpWidget(host(active: ThisOrThatTab.thisOption));
    await tester.pumpAndSettle();

    expect(find.text('Night in, nowhere to be'), findsOneWidget);
    expect(find.text('Night in or night out?'), findsOneWidget);
    expect(find.text('Night out, somewhere loud'), findsNothing);
  });

  testWidgets('choosing THAT shows option B', (tester) async {
    await tester.pumpWidget(host(active: ThisOrThatTab.thatOption));
    await tester.pumpAndSettle();

    expect(find.text('Night out, somewhere loud'), findsOneWidget);
    expect(find.text('Night in, nowhere to be'), findsNothing);
  });

  testWidgets('each side tab reports which choice it is', (tester) async {
    final chosen = <ThisOrThatTab>[];
    await tester.pumpWidget(
      host(active: ThisOrThatTab.question, onSelect: chosen.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('THIS'));
    await tester.tap(find.text('THAT'));
    await tester.pump();

    expect(chosen, [ThisOrThatTab.thisOption, ThisOrThatTab.thatOption]);
  });

  testWidgets('the middle tab is not a way to un-answer', (tester) async {
    // An answer you can take back is not the commitment this game asks
    // for, so OR is deliberately inert.
    final chosen = <ThisOrThatTab>[];
    await tester.pumpWidget(
      host(active: ThisOrThatTab.thisOption, onSelect: chosen.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OR'), warnIfMissed: false);
    await tester.pump();

    expect(chosen, isEmpty);
  });

  testWidgets('a null handler makes every tab inert', (tester) async {
    // Null while submitting, so a committed answer cannot change
    // mid-flight.
    await tester.pumpWidget(host(active: ThisOrThatTab.question));
    await tester.pumpAndSettle();

    for (final label in ['THIS', 'OR', 'THAT']) {
      await tester.tap(find.text(label), warnIfMissed: false);
    }
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a screen reader is told which tab is forward', (tester) async {
    // The colour flooding IS the confirmation for a sighted player, so
    // without this the accessibility path has no confirmation at all --
    // the same gap the Paint Ball review found on its aimed bay.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(host(active: ThisOrThatTab.thisOption));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text('THIS')).hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
    expect(
      tester.getSemantics(find.text('THAT')).hasFlag(SemanticsFlag.isSelected),
      isFalse,
      reason: 'a positive control for the assertion above',
    );

    handle.dispose();
  });

  testWidgets('a long option does not overflow the card', (tester) async {
    // Custom questions allow 50 characters per option, and the answer
    // renders at 26pt.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              child: ThisOrThatTabCard(
                questionText:
                    'When the week has been hard, which of these actually '
                    'helps you come back to yourself?',
                optionA: 'A long quiet evening with absolutely nothing in it',
                optionB: 'Somewhere loud enough to stop me thinking at all',
                active: ThisOrThatTab.thisOption,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
