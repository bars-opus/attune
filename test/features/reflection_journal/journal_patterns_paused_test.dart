// Spec 1 W1c (D12), batch 6 fix round 1 (controller ruling): while
// journal_ai_insights is off, get_patterns answers {status: 'paused'}; the
// Patterns tab says so instead of showing a blank page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_journal.dart';
import 'support/journal_test_app.dart';

class _PatternsRepository extends FakeJournalRepository {
  _PatternsRepository(this.status) : super(now: DateTime.now());

  final String status;

  @override
  Future<({String status, String? summary, int entryCount})>
  getPatterns() async => (status: status, summary: null, entryCount: 4);
}

Finder get _blankText =>
    find.byWidgetPredicate((w) => w is Text && (w.data ?? 'x').isEmpty);

void main() {
  testWidgets('paused patterns say so, and no blank summary is shown', (
    t,
  ) async {
    await pumpJournal(t, repo: _PatternsRepository('paused'));
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();

    expect(find.text('Patterns are paused for now'), findsOneWidget);
    expect(
      find.text('Your entries are saved and stay private to you.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.pattern), findsWidgets);
    expect(_blankText, findsNothing);
  });

  testWidgets('a completed summary is not read as paused', (t) async {
    await pumpJournal(t, repo: _PatternsRepository('completed'));
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();

    expect(find.text('Patterns are paused for now'), findsNothing);
  });
}
