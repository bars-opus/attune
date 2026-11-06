// Spec 1 W10a: Healing and the journal at large text (audit order: 5th and
// 6th). Healing's reflection stage before and after the reflection comes
// back, and with the support card; the journal list and an entry with a
// reflection under it.
//   flutter test --update-goldens test/accessibility/w10/healing_journal_large_text_test.dart
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/screens/healing_post_mortem_screen.dart';
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/healing/w9e/support/healing_fakes.dart';
import '../../features/reflection_journal/support/fake_journal.dart';
import '../../features/reflection_journal/support/journal_test_app.dart';
import '../../helpers/flow_harness.dart';
import 'support/large_text_audit.dart';

const _observation =
    'You both seemed to wait for the other to start the hard conversations, '
    'and the quiet between you grew a little each time.';

Future<void> _golden(String name, Size phone, double scale) async {
  if (phone != auditPhones.first || !goldenScales.contains(scale)) return;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.${scaleName(scale)}.png'),
  );
}

void main() {
  for (final phone in auditPhones) {
    for (final scale in auditScales) {
      final where = '${phone.width.toInt()} wide, text $scale';

      testWidgets('Healing reflection stage, $where', (t) async {
        for (final (name, answer) in [
          ('healing_ready', <String, dynamic>{}),
          (
            'healing_done',
            <String, dynamic>{
              'status': 'completed',
              'observation': _observation,
            },
          ),
          ('healing_support', <String, dynamic>{'status': 'support_offered'}),
        ]) {
          final overflows = await collectOverflows(() async {
            await pumpFlowScreen(
              t,
              () => HealingPostMortemScreen(journey: testJourney()),
              textScale: scale,
              rootTextScaleCap: scale,
              size: phone,
              overrides: [
                healingGenerationServiceProvider.overrideWithValue(
                  FakeHealingGeneration([answer]),
                ),
                healingRepositoryProvider.overrideWithValue(
                  FakeHealingRepository(),
                ),
                healingAccountProvider.overrideWith((ref) => 'ama'),
              ],
            );
            if (name != 'healing_ready') {
              // Below the fold once large text scrolls the stage.
              await t.ensureVisible(find.text('Generate reflection'));
              await t.pumpAndSettle();
              await t.tap(find.text('Generate reflection'));
              await t.pumpAndSettle();
            }
            await _golden(name, phone, scale);
            await scrollToEnd(t);
          });
          expect(overflows, isEmpty, reason: name);
        }
      });

      testWidgets('journal list and entry, $where', (t) async {
        final repo = FakeJournalRepository();
        final entry = repo.addEntry(
          title: 'Sunday walk by the lagoon',
          text: 'We talked about moving closer to my mother next year.',
        );
        repo.addEntry(text: 'A short note.');
        repo.analysisFor = JournalAnalysis(
          status: 'completed',
          observation: _observation,
          tone: 'hopeful',
        );
        setPhone(t, phone, scale);
        final overflows = await collectOverflows(() async {
          final router = await pumpJournal(t, repo: repo);
          setPhone(t, phone, scale);
          await t.pumpAndSettle();
          await _golden('journal_list', phone, scale);
          await scrollToEnd(t);
          router.push(
            '/journalEntry',
            extra: JournalEntryArgs(entryId: entry.id, isNew: false),
          );
          await t.pumpAndSettle();
          await _golden('journal_entry', phone, scale);
          await scrollToEnd(t);
        });
        expect(overflows, isEmpty);
      });
    }
  }
}
