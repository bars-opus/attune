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
  final appRouter = File('lib/app/routing/app_router.dart').readAsStringSync();

  test('the conversations screen renders the planning summary row', () {
    expect(
      conversationsScreen.contains('_PlanningSummaryRow()'),
      isTrue,
      reason: 'without this the entry point into Planning is unreachable from chat',
    );
  });

  test('the planning route is registered and builds PlanningHomeScreen', () {
    expect(appRouter.contains("name: 'planning'"), isTrue);
    expect(appRouter.contains('PlanningHomeScreen(relationshipId: relationshipId)'), isTrue);
  });

  test('the row passes the relationship id through, not a null/empty extra', () {
    expect(
      RegExp(
        r"pushNamed\('planning', extra: relationshipId\)",
      ).hasMatch(conversationsScreen),
      isTrue,
      reason:
          'the row must be scoped to the current relationship; passing '
          'the wrong id would read as an empty Planning home rather than an error',
    );
  });
}
