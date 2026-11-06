// Spec 1 W9c (§8 W9c, §6.6, §2.2, §2.3): when the crisis check answers
// support_offered, the writer sees the support card instead of a
// reflection: on the journal list when they leave the entry, in the entry
// when they open it again, and on the Patterns tab. "See support" opens
// Support (counted); "Not now" puts it away. Nothing about it is stored on
// the phone. "Need support now?" is always in the entry menu (batch-8
// ruling I-4: support never waits for journal_ai_insights).
//   flutter test --update-goldens test/features/reflection_journal/w9/journal_support_test.dart
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_support_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/flow_harness.dart';
import '../support/fake_journal.dart';
import '../support/journal_test_app.dart';
import '../../../helpers/tap_in_reach.dart';

const _card =
    "If things feel heavy right now, you don't have to carry it alone. Support is here if you want it.";

/// The server's crisis check matched every entry.
class _SupportOffered extends FakeJournalRepository {
  _SupportOffered() : super(now: DateTime.now());

  @override
  Future<JournalAnalysis> analyseEntry(String entryId) async {
    analysed.add(entryId);
    return JournalAnalysis.fromJson(const {'status': 'support_offered'});
  }

  @override
  Future<({String status, String? summary, int entryCount})>
  getPatterns() async => (
    status: 'support_offered',
    summary: null,
    entryCount: 0,
  );
}

Future<void> _type(WidgetTester t, String text) async {
  t
      .state<NoteTextBlockState>(find.byType(NoteTextBlock).first)
      .controller
      .replaceText(0, 0, text, TextSelection.collapsed(offset: text.length));
  await t.pump();
}

Future<void> _back(WidgetTester t) async {
  t.state<NavigatorState>(find.byType(Navigator).first).pop();
  await t.pumpAndSettle();
}

void main() {
  test('support_offered is read as such', () {
    final a = JournalAnalysis.fromJson(const {'status': 'support_offered'});
    expect(a.isSupportOffered, isTrue);
    expect(a.isComplete, isFalse);
  });

  testWidgets(
    'leaving an entry that reads as a crisis: the card, never a reflection',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final repo =
          _SupportOffered()
            ..analysisFor = JournalAnalysis.fromJson(const {
              'status': 'completed',
              'tone': 'heavy',
              'observation': 'An older reflection.',
              'confidence': 'low',
            });
      final e = repo.addEntry(title: 'Tonight', text: '');
      await pumpJournal(t, repo: repo);
      expect(find.text(_card), findsNothing);
      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      await _type(t, 'Words the check reads as a crisis');
      await _back(t);
      await t.pumpAndSettle();
      expect(repo.analysed, [e.id]);
      expect(find.text(_card), findsOneWidget); // on the list

      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      expect(find.text(_card), findsOneWidget); // in the entry, instead of
      expect(find.text('An older reflection.'), findsNothing); // the reflection
      await tapInReach(t, find.text('Not now'));
      await t.pumpAndSettle();
      expect(find.text(_card), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('support')), isEmpty);
    },
  );

  testWidgets('"Not now" on the list puts it away', (t) async {
    final repo = _SupportOffered();
    repo.addEntry(title: 'Late', text: '');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Late'));
    await t.pumpAndSettle();
    await _type(t, 'More words');
    await _back(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(find.text(_card), findsNothing);
  });

  testWidgets('the card is a live region, so a screen reader is told it '
      'arrived (W9 final M-7)', (t) async {
    final repo = _SupportOffered();
    repo.addEntry(title: 'Later', text: '');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Later'));
    await t.pumpAndSettle();
    await _type(t, 'Some words');
    await _back(t);
    await t.pumpAndSettle();
    expect(find.text(_card), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text(_card),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Patterns: support instead of a summary', (t) async {
    final repo = _SupportOffered();
    repo.addEntry(title: 'One', text: 'x');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();
    expect(find.text(_card), findsOneWidget);
  });

  testWidgets(
    'the entry menu always has "Need support now?": it opens Support, counted',
    (t) async {
      final metrics = <String>[];
      final repo = FakeJournalRepository(now: DateTime.now());
      final e = repo.addEntry(title: 'Menu', text: 'x');
      await pumpJournal(
        t,
        repo: repo,
        initial: '/journalEntry',
        extra: JournalEntryArgs(entryId: e.id),
        overrides: [
          metricCounterProvider.overrideWithValue(
            MetricCounter((key) async => metrics.add(key)),
          ),
        ],
      );
      await t.tap(find.byTooltip('Entry options'));
      await t.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      await t.tap(find.text('Need support now?'));
      await t.pumpAndSettle();
      expect(find.text('Support resources screen'), findsOneWidget);
      expect(metrics, ['support_link_opened:journal']);
    },
  );

  testWidgets(
    'the card: See support is counted and opens Support; guidelines and goldens',
    (t) async {
      var notNow = 0;
      Widget card() => Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: JournalSupportCard(onNotNow: () => notNow++),
        ),
      );
      final h = await pumpFlowScreen(t, card);
      await expectFlowGuidelines(t);
      await t.tap(find.text('Not now'));
      expect(notNow, 1);
      await t.tap(find.text('See support'));
      await t.pumpAndSettle();
      expect(find.text('at /safety-resources'), findsOneWidget);
      expect(h.metrics, ['support_link_opened:journal']);
      await expectFlowGoldens(t, 'journal_support_card', card);
    },
  );
}
