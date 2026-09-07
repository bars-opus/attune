import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/games/this_or_that/data/models/custom_this_or_that_question.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_custom_providers.dart'
    as custom;
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_custom_create_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_custom_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _screen({
  List<CustomThisOrThatQuestion> mine = const [],
  List<CustomThisOrThatQuestion> partner = const [],
}) {
  return ProviderScope(
    overrides: [
      custom.myThisOrThatCustomQuestionsProvider.overrideWith(
        (_) async => mine,
      ),
      custom.partnerThisOrThatCustomQuestionsProvider.overrideWith(
        (_) async => partner,
      ),
      custom.partnerNameProvider.overrideWith((_) async => 'Ama'),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const ThisOrThatCustomListScreen(),
    ),
  );
}

void main() {
  testWidgets('custom decks explain both empty states', (tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    expect(find.text('Our question decks'), findsOneWidget);
    expect(find.text('Your deck is waiting'), findsOneWidget);
    expect(find.text('Write a question'), findsOneWidget);

    await tester.tap(find.text('Ama'));
    await tester.pumpAndSettle();

    expect(find.text('Ama has not shared a question yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long custom choices remain readable without overflow', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final question = CustomThisOrThatQuestion(
      id: 'custom-1',
      userId: 'user-a',
      questionText: 'How would we spend a completely free weekend together?',
      optionA: 'Stay home, cook something ambitious, and build a blanket fort',
      optionB: 'Take the earliest train somewhere new with no plans at all',
      emojiA: '🏠',
      emojiB: '🚆',
      tone: 'playful',
      isPrivate: false,
      timesUsed: 12,
      createdAt: DateTime(2026, 9, 1),
    );

    await tester.pumpWidget(_screen(mine: [question]));
    await tester.pumpAndSettle();

    expect(find.text(question.questionText), findsOneWidget);
    expect(find.textContaining('Stay home, cook'), findsOneWidget);
    expect(find.textContaining('Take the earliest train'), findsOneWidget);
    expect(find.text('Played 12 times'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create form enables save as a complete draft is entered', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ThisOrThatCustomCreateScreen(),
        ),
      ),
    );
    await tester.pump();

    FilledButton saveButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add to my deck'),
    );

    expect(saveButton().onPressed, isNull);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'Perfect Sunday?');
    await tester.enterText(fields.at(1), 'Stay home');
    await tester.enterText(fields.at(2), 'Head outside');
    await tester.pump();

    expect(saveButton().onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
