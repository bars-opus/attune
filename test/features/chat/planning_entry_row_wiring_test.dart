import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Planning's entry row reaches the actual conversations screen, and
/// the route it opens actually resolves to PlanningHomeScreen.
///
/// Following story_calendar_wiring_test.dart's precedent for the same
/// shape of gap: ConversationsScreen needs Supabase, a relationship,
/// and several live providers to build, so nothing in test/ mounts it.
/// A widget test of `_PlanningSummaryRow` in isolation (if one existed)
/// would prove the row behaves correctly and say nothing about whether
/// ConversationsScreen ever renders it.
void main() {
  final conversationsScreen = File(
    'lib/features/chat/presentation/screens/conversations_screen.dart',
  ).readAsStringSync();
  final cards = File(
    'lib/features/chat/presentation/widgets/conversations_home_cards.dart',
  ).readAsStringSync();
  final appRouter = File('lib/app/routing/app_router.dart').readAsStringSync();

  test('the conversations screen renders the journals and together cards', () {
    // A usage, not the class itself: these live in conversations_home_cards.dart,
    // so any occurrence in the screen is a place it's built.
    expect(RegExp(r'JournalsCard\(').hasMatch(conversationsScreen), isTrue,
        reason: 'the way into both journals is on the conversations screen');
    expect(RegExp(r'TogetherCard\(').hasMatch(conversationsScreen), isTrue,
        reason: 'the together card is on the conversations screen');
  });

  test('the planning route is registered and builds PlanningHomeScreen', () {
    expect(appRouter.contains("name: 'planning'"), isTrue);
    expect(appRouter.contains('PlanningHomeScreen(relationshipId: relationshipId)'), isTrue);
  });

  test('the row passes the relationship id through, not a null/empty extra', () {
    expect(
      RegExp(
        r"pushNamed\('planning', extra: relationshipId\)",
      ).hasMatch(cards),
      isTrue,
      reason:
          'the row must be scoped to the current relationship; passing '
          'the wrong id would read as an empty Planning home rather than an error',
    );
  });
}
