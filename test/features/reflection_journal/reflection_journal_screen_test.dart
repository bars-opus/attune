// test/features/reflection_journal/reflection_journal_screen_test.dart
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reflection_journal/presentation/screens/reflection_journal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// journalEntriesProvider is an AsyncNotifierProvider (cache-then-refresh —
/// see JournalEntriesNotifier), so overriding it in tests means supplying a
/// fake notifier rather than a plain async callback.
class _FakeJournalEntriesNotifier extends JournalEntriesNotifier {
  _FakeJournalEntriesNotifier(this._entries);
  final List<JournalEntry> _entries;

  @override
  Future<List<JournalEntry>> build() async => _entries;
}

void main() {
  Widget wrap(List<Override> overrides) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => const ReflectionJournalScreen(),
        ),
      ),
    );
  }

  testWidgets('shows empty state when there are no entries', (tester) async {
    await tester.pumpWidget(
      wrap([
        journalEntriesProvider.overrideWith(
          () => _FakeJournalEntriesNotifier(const []),
        ),
        journalPatternsProvider.overrideWith(
          (ref) async => (status: 'insufficient_evidence', summary: null, entryCount: 0),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Write'), findsWidgets);
  });

  testWidgets('shows entry cards when entries are present', (tester) async {
    final entry = JournalEntryFixture.one();
    await tester.pumpWidget(
      wrap([
        journalEntriesProvider.overrideWith(
          () => _FakeJournalEntriesNotifier([entry]),
        ),
        journalPatternsProvider.overrideWith(
          (ref) async => (status: 'insufficient_evidence', summary: null, entryCount: 1),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text(entry.content), findsOneWidget);
  });

  testWidgets('patterns tab shows not-enough-entries state below threshold', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap([
        journalEntriesProvider.overrideWith(
          () => _FakeJournalEntriesNotifier(const []),
        ),
        journalPatternsProvider.overrideWith(
          (ref) async => (status: 'insufficient_evidence', summary: null, entryCount: 1),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Patterns'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not enough entries'), findsOneWidget);
  });
}

class JournalEntryFixture {
  static JournalEntry one() {
    return _fixtureEntry;
  }
}

final _fixtureEntry = _buildEntry();

JournalEntry _buildEntry() {
  return JournalEntry(
    id: 'entry-1',
    userId: 'user-1',
    content: 'Today I noticed I felt calmer than usual.',
    promptUsed: null,
    tone: null,
    createdAt: DateTime(2026, 8, 1),
    updatedAt: DateTime(2026, 8, 1),
  );
}
