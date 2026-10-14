import 'dart:async';

import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/planning/presentation/widgets/planning_ribbon.dart';
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_photo_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_journal.dart';
import 'support/journal_test_app.dart';

Future<void> _type(WidgetTester t, String text, {int block = 0}) async {
  t.state<NoteTextBlockState>(find.byType(NoteTextBlock).at(block)).controller.replaceText(
      0, 0, text, TextSelection.collapsed(offset: text.length));
  await t.pump();
}

Future<void> _back(WidgetTester t) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.pop();
  await t.pumpAndSettle();
}

Finder _ribbon(String label) => find.descendant(of: find.byType(PlanningRibbon), matching: find.text(label));

void main() {
  testWidgets('a new entry opens ready to write, with a prompt that can be dismissed', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    await pumpJournal(t, repo: repo);
    await t.tap(find.byTooltip('New entry'));
    await t.pumpAndSettle();
    expect(find.byType(NoteTextBlock), findsOneWidget);
    final prompt = repo.entries.values.single.promptUsed!;
    expect(find.text(prompt), findsOneWidget);
    await t.tap(find.byTooltip('Dismiss prompt'));
    await t.pumpAndSettle();
    expect(find.text(prompt), findsNothing);
  });

  testWidgets('typing saves itself and titles an untitled entry from its first line', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(text: '');
    await pumpJournal(t, repo: repo, initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    await _type(t, 'Quiet morning\nThen a long walk');
    await t.pump(NoteTextBlock.debounce);
    await t.pumpAndSettle();
    expect(repo.saves.last, 'Quiet morning\nThen a long walk');
    expect(repo.entries[e.id]!.title, 'Quiet morning');
  });

  testWidgets('a new entry left empty is discarded', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    await pumpJournal(t, repo: repo);
    await t.tap(find.byTooltip('New entry'));
    await t.pumpAndSettle();
    final id = repo.entries.keys.single;
    await _back(t);
    expect(repo.purged, [id]);
    expect(find.byType(JournalEntryScreen), findsNothing);
  });

  testWidgets('leaving right after typing saves, then reflects once', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Day', text: '');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Day'));
    await t.pumpAndSettle();
    await _type(t, 'Something to think about');
    await _back(t); // within the debounce
    await t.pumpAndSettle();
    expect(repo.saves, ['Something to think about']);
    expect(repo.analysed, [e.id]);
  });

  testWidgets('a save still on its way when leaving is waited for before reflecting', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Slow', text: '');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Slow'));
    await t.pumpAndSettle();
    repo.saveGate = Completer<void>();
    await _type(t, 'Written on a slow train');
    await t.pump(NoteTextBlock.debounce); // the save is now on its way
    await _back(t);
    expect(repo.analysed, isEmpty); // not on the old text
    repo.saveGate!.complete();
    await t.pumpAndSettle();
    expect(repo.saves, ['Written on a slow train']);
    expect(repo.analysed, [e.id]);
  });

  testWidgets('reading an entry never calls the AI', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    repo.addEntry(title: 'Old one', text: 'Written before notes');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Old one'));
    await t.pumpAndSettle();
    await _back(t);
    expect(repo.analysed, isEmpty);
    expect(repo.saves, isEmpty);
  });

  testWidgets('a stale save asks before overwriting', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Two phones', text: 'Start');
    await pumpJournal(t, repo: repo, initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    repo.conflictNext = true;
    await _type(t, 'Mine ');
    await t.pump(NoteTextBlock.debounce);
    await t.pumpAndSettle();
    expect(find.text('You changed this on another device'), findsOneWidget);
  });

  testWidgets('Insert offers only Text and Photo; a photo lands in the owner\'s folder', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final media = FakeJournalMedia();
    final e = repo.addEntry(title: 'With a photo', text: 'Look');
    await pumpJournal(t, repo: repo, media: media, photos: [[1, 2, 3]],
        initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    await t.tap(_ribbon('Insert'));
    await t.pumpAndSettle();
    expect(_ribbon('Checklist'), findsNothing);
    await t.tap(_ribbon('Photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    expect(media.uploads.single, startsWith('$fakeJournalUser/${e.id}/'));
    expect(find.byType(JournalPhotoBlock), findsOneWidget);
  });

  testWidgets('a failed upload adds nothing and offers Retry', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final media = FakeJournalMedia()..fail = true;
    final e = repo.addEntry(title: 'Offline', text: 'x');
    await pumpJournal(t, repo: repo, media: media, photos: [[1, 2, 3]],
        initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    await t.tap(_ribbon('Insert'));
    await t.pumpAndSettle();
    await t.tap(_ribbon('Photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    expect(find.byType(JournalPhotoBlock), findsNothing);
    expect(repo.blocks[e.id]!.where((b) => b.isPhoto), isEmpty);
    expect(find.textContaining("Couldn't add this photo"), findsOneWidget);
    media.fail = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.byType(JournalPhotoBlock), findsOneWidget);
  });

  testWidgets('a photo can be removed', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Pics', text: 'x', photo: true);
    await pumpJournal(t, repo: repo, initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    await t.tap(find.byTooltip('Options for photo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(find.byType(JournalPhotoBlock), findsNothing);
  });

  testWidgets('a finished reflection shows under the writing', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now())
      ..analysisFor = JournalAnalysis.fromJson(const {
        'status': 'completed', 'tone': 'hopeful', 'observation': 'Based on what you wrote, rest mattered today.',
        'confidence': 'medium',
      });
    final e = repo.addEntry(title: 'Reflected', text: 'x');
    await pumpJournal(t, repo: repo, initial: '/journalEntry', extra: JournalEntryArgs(entryId: e.id));
    expect(find.text('A reflection'), findsOneWidget);
    expect(find.textContaining('rest mattered today'), findsOneWidget);
  });

  testWidgets('delete from the menu removes the entry for good', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Bye', text: 'x');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Bye'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Entry options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete').last); // the confirmation's button
    await t.pumpAndSettle();
    expect(repo.purged, [e.id]);
    expect(find.text('Bye'), findsNothing);
  });
}
