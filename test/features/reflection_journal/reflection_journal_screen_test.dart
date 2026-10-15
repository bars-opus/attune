import 'package:attune/core/notes/note_section.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_entry_row.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_journal.dart';
import 'support/journal_test_app.dart';

void main() {
  testWidgets('entries are grouped by the day written, each group a card of rows', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final now = DateTime.now();
    repo.addEntry(title: 'Evening', text: 'Long day, good talk', createdAt: now.subtract(const Duration(minutes: 5)));
    repo.addEntry(text: 'Untitled thoughts', createdAt: now.subtract(const Duration(days: 1)));
    repo.addEntry(title: 'Pinned', text: 'Keep this', pinned: true, createdAt: now.subtract(const Duration(days: 40)));
    await pumpJournal(t, repo: repo);
    expect(find.text('Pinned'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsWidgets);
    expect(find.byType(NoteSection), findsNWidgets(3));
    expect(find.byType(InfoRowWidget), findsNWidgets(3));
  });

  testWidgets('a row is its title on top and one date below, as in notes', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    repo.addEntry(title: 'Evening', text: 'Long day, good talk', createdAt: DateTime(2026, 3, 3, 10));
    repo.addEntry(text: 'No title here', createdAt: DateTime(2026, 3, 2, 10));
    await pumpJournal(t, repo: repo);
    final rows = t.widgetList<InfoRowWidget>(find.byType(InfoRowWidget)).toList();
    expect(rows.map((r) => r.title), ['Evening', 'No title here']); // untitled: its first words
    expect(rows.map((r) => r.subtitle), ['Tuesday, March 3, 2026', 'Monday, March 2, 2026']);
    expect(find.textContaining('Long day, good talk'), findsNothing); // one date, nothing after it
  });

  testWidgets('swipe right deletes with Undo; swipe left pins', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Swipe me', text: 'x');
    await pumpJournal(t, repo: repo);
    await t.drag(find.text('Swipe me'), const Offset(500, 0));
    await t.pumpAndSettle();
    expect(find.text('Swipe me'), findsNothing);
    expect(repo.softDeleted, {e.id});
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(find.text('Swipe me'), findsOneWidget);
    await t.drag(find.text('Swipe me'), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(repo.entries[e.id]!.pinnedAt, isNotNull);
    expect(find.text('Pinned'), findsOneWidget);
    await t.pump(JournalEntryRow.undoWindow); // the purge timer runs out (Undo was used: nothing purged)
    expect(repo.purged, isEmpty);
  });

  testWidgets('opening the journal sweeps old deletions once', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    await pumpJournal(t, repo: repo);
    expect(repo.sweeps, 1);
  });

  testWidgets('+ creates an entry and opens it, ready to write', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    await pumpJournal(t, repo: repo);
    await t.tap(find.byTooltip('New entry'));
    await t.pumpAndSettle();
    expect(find.byType(JournalEntryScreen), findsOneWidget);
    expect(repo.entries, hasLength(1));
  });

  testWidgets('the empty journal says nothing is shared', (t) async {
    await pumpJournal(t, repo: FakeJournalRepository(now: DateTime.now()));
    expect(find.textContaining('Nothing here is ever shared with anyone.'), findsOneWidget);
  });
}
