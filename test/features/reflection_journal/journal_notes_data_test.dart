import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_journal.dart';

ProviderContainer _container(FakeJournalRepository repo, {FakeJournalMedia? media}) {
  final c = ProviderContainer(overrides: [
    reflectionJournalRepositoryProvider.overrideWithValue(repo),
    journalMediaGatewayProvider.overrideWithValue(media ?? FakeJournalMedia()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('the list loads pinned apart, and sweeps old deletions once', () async {
    final repo = FakeJournalRepository();
    repo.addEntry(text: 'Pinned one', pinned: true);
    repo.addEntry(text: 'Plain one');
    final c = _container(repo);
    final s = await c.read(journalListProvider.future);
    expect(s.pinned.single.snippet, 'Pinned one');
    expect(s.entries.single.snippet, 'Plain one');
    expect(repo.sweeps, 1);
  });

  test('delete hides at once; Undo restores; a discarded entry never comes back on refresh', () async {
    final repo = FakeJournalRepository();
    final e = repo.addEntry(text: 'Gone soon');
    final keep = repo.addEntry(text: 'Stays');
    final c = _container(repo);
    final row = (await c.read(journalListProvider.future)).entries.firstWhere((x) => x.id == e.id);
    await c.read(journalListProvider.notifier).delete(row);
    expect(c.read(journalListProvider).value!.entries.map((x) => x.id), [keep.id]);
    await c.read(journalListProvider.notifier).restore(e.id);
    expect(c.read(journalListProvider).value!.entries.map((x) => x.id), contains(e.id));
    c.read(journalListProvider.notifier).forget(e.id);
    await c.read(journalListProvider.notifier).refresh();
    expect(c.read(journalListProvider).value!.entries.map((x) => x.id), [keep.id]);
  });

  test('a stale text save is a conflict, not an overwrite', () async {
    final repo = FakeJournalRepository();
    final e = repo.addEntry(text: 'Hello');
    final c = _container(repo);
    final d = await c.read(journalEntryDetailProvider(e.id).future);
    repo.conflictNext = true;
    final r = await c.read(journalEntryDetailProvider(e.id).notifier)
        .saveText(d.blocks.first.id, 1, const [{'insert': 'Mine\n'}]);
    expect(r, isA<NoteConflict>());
    expect((r as NoteConflict).plainText.trim(), 'From my other phone');
  });

  test('inserting mid-paragraph splits the text around the new block', () async {
    final repo = FakeJournalRepository();
    final e = repo.addEntry(text: 'Before after');
    final c = _container(repo);
    final d = await c.read(journalEntryDetailProvider(e.id).future);
    await c.read(journalEntryDetailProvider(e.id).notifier).insertAtCursor(
      'photo',
      textBlockId: d.blocks.first.id,
      version: d.blocks.first.version,
      before: const [{'insert': 'Before\n'}],
      after: const [{'insert': 'after\n'}],
      payload: {'path': '$fakeJournalUser/${e.id}/p.jpg'},
    );
    final kinds = c.read(journalEntryDetailProvider(e.id)).value!.blocks.map((b) => b.kind);
    expect(kinds, ['text', 'photo', 'text']);
    expect(repo.entries[e.id]!.content, 'Before\n\nafter');
  });

  test('photo paths live in the owner\'s own entry folder', () async {
    final repo = FakeJournalRepository();
    final e = repo.addEntry(text: 'x');
    final c = _container(repo);
    await c.read(journalEntryDetailProvider(e.id).future);
    final path = c.read(journalEntryDetailProvider(e.id).notifier).newPhotoPath();
    expect(path, matches(RegExp('^$fakeJournalUser/${e.id}/[0-9a-f-]{36}\\.jpg\$')));
  });

  test('snippets and row titles never carry more than 80 characters', () {
    expect(journalSnippet('a  b\n\nc'), 'a b c');
    expect(journalSnippet('x' * 200).length, 80);
    expect(journalRowTitle(null), 'Start your first reflection');
    final e = JournalEntry(id: '1', userId: 'u', content: 'Body text', createdAt: DateTime(2026), updatedAt: DateTime(2026));
    expect(journalRowTitle(e), 'Body text');
    expect(journalRowTitle(e.copyWith(title: 'My title')), 'My title');
  });

  test('closing an entry refreshes the Conversations reflection line too', () async {
    final repo = FakeJournalRepository();
    var builds = 0;
    final c = ProviderContainer(overrides: [
      reflectionJournalRepositoryProvider.overrideWithValue(repo),
      journalMediaGatewayProvider.overrideWithValue(FakeJournalMedia()),
      journalEntriesProvider.overrideWith(() => _CountingEntries(() => builds++)),
    ]);
    addTearDown(c.dispose);
    c.listen(journalEntriesProvider, (_, __) {});
    await c.read(journalEntriesProvider.future);
    await c.read(journalListProvider.future);
    expect(builds, 1);
    await c.read(journalListProvider.notifier).refresh(); // what closing an entry does
    await c.read(journalEntriesProvider.future);
    expect(builds, 2);
  });
}

class _CountingEntries extends JournalEntriesNotifier {
  _CountingEntries(this.onBuild);
  final void Function() onBuild;
  @override
  Future<List<JournalEntry>> build() async {
    onBuild();
    return const [];
  }
}
