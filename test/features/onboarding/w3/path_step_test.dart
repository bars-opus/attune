// Spec 1 W3a (§3.7 A6, §2.2, §2.3): three equal cards, nothing preselected,
// a radio group; Continue only after a choice; "Not open in {country} yet"
// from the D15 list and the person's own number; errors read out.
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/widgets/path_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

void main() {
  testWidgets('nothing preselected; Continue waits for a choice', (
    tester,
  ) async {
    final chosen = <AppPath>[];
    await pumpFlowScreen(tester, () => PathStep(onContinue: chosen.add));
    expect(find.text('What brings you to Attune?'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Just for me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(chosen, [AppPath.justMe]);
  });

  testWidgets('a radio group: the chosen card reads as checked', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(tester, () => PathStep(onContinue: (_) {}));
    expect(find.bySemanticsLabel('Choose one of three'), findsOneWidget);
    await tester.tap(find.text('In a relationship'));
    await tester.pumpAndSettle();
    final node = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^In a relationship\. A private space')),
    );
    expect(node.hasFlag(SemanticsFlag.isChecked), isTrue);
    expect(node.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
    semantics.dispose();
  });

  testWidgets('Dating says "Not open in {country} yet" only outside the list', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => const PathStep(
        onContinue: _noop,
        ownCountry: 'NG',
        openCountries: ['GB', 'GH'],
      ),
    );
    expect(find.text('Not open in Nigeria yet'), findsOneWidget);

    await pumpFlowScreen(
      tester,
      () => const PathStep(
        onContinue: _noop,
        ownCountry: 'GH',
        openCountries: ['GB', 'GH'],
      ),
    );
    expect(find.textContaining('Not open in'), findsNothing);

    // Never read (D15): no claim either way.
    await pumpFlowScreen(
      tester,
      () => const PathStep(onContinue: _noop, ownCountry: 'NG'),
    );
    expect(find.textContaining('Not open in'), findsNothing);
  });

  testWidgets('the Just for me card says it is for anyone', (tester) async {
    await pumpFlowScreen(tester, () => const PathStep(onContinue: _noop));
    expect(
      find.text(
        'Your journal, quizzes and Healing. Single, partnered or in between.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'You can change this any time. Your journal and quizzes are yours whichever you choose.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an error is shown with its icon', (tester) async {
    await pumpFlowScreen(
      tester,
      () => const PathStep(
        onContinue: _noop,
        errorText: "Dating needs a connection. Try again when you're online.",
      ),
    );
    expect(
      find.text("Dating needs a connection. Try again when you're online."),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('meets the tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      () => PathStep(onContinue: (_) {}, onAlreadyInvited: () {}),
    );
    await tester.tap(find.text('Single and open to dating'));
    await tester.pumpAndSettle();
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('A6 goldens', (tester) async {
    await expectFlowGoldens(
      tester,
      'a6_path',
      () => PathStep(
        onContinue: (_) {},
        onAlreadyInvited: () {},
        ownCountry: 'NG',
        openCountries: const ['GB', 'GH'],
      ),
    );
  });
}

void _noop(AppPath _) {}
