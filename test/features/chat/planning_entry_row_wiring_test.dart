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
    // `_PlanningSummaryRow()` also appears once in the class's own
    // constructor declaration (`const _PlanningSummaryRow();`), which
    // is present whether or not the widget is ever placed in the
    // render tree. Requiring at least 2 occurrences means at least one
    // of them has to be a usage site (in the Column's children, or
    // anywhere else the widget is actually instantiated) rather than
    // just the declaration — this is what makes the assertion fail if
    // only the widget-tree usage line is removed, per the plan's
    // no-vacuous-test constraint.
    final occurrences = RegExp(
      r'_PlanningSummaryRow\(\)',
    ).allMatches(conversationsScreen).length;
    expect(
      occurrences,
      greaterThanOrEqualTo(2),
      reason:
          'without a usage site (not just the class declaration), the '
          'entry point into Planning is unreachable from chat',
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
