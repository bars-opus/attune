import 'package:attune/features/healing/presentation/providers/healing_providers.dart'
    show supabaseClientProvider;
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/data/repositories/reflection_journal_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reflectionJournalRepositoryProvider =
    Provider<ReflectionJournalRepository>((ref) {
      return ReflectionJournalRepository(ref.read(supabaseClientProvider));
    });

final journalEntriesProvider = FutureProvider<List<JournalEntry>>((
  ref,
) async {
  return ref.read(reflectionJournalRepositoryProvider).getEntries();
});

final journalEntryProvider = FutureProvider.family<JournalEntry, String>((
  ref,
  entryId,
) async {
  return ref.read(reflectionJournalRepositoryProvider).getEntry(entryId);
});

final journalPatternsProvider =
    FutureProvider<({String status, String? summary, int entryCount})>((
      ref,
    ) async {
      return ref.read(reflectionJournalRepositoryProvider).getPatterns();
    });

final createJournalEntryProvider = FutureProvider.family<
  String,
  ({String content, String? promptUsed})
>((ref, params) async {
  final entryId = await ref
      .read(reflectionJournalRepositoryProvider)
      .createEntry(content: params.content, promptUsed: params.promptUsed);
  ref.invalidate(journalEntriesProvider);
  return entryId;
});

final updateJournalEntryProvider =
    FutureProvider.family<void, ({String entryId, String content})>((
      ref,
      params,
    ) async {
      await ref
          .read(reflectionJournalRepositoryProvider)
          .updateEntry(entryId: params.entryId, content: params.content);
      ref.invalidate(journalEntriesProvider);
      ref.invalidate(journalEntryProvider(params.entryId));
      ref.invalidate(analyseJournalEntryProvider(params.entryId));
    });

final deleteJournalEntryProvider = FutureProvider.family<void, String>((
  ref,
  entryId,
) async {
  await ref.read(reflectionJournalRepositoryProvider).deleteEntry(entryId);
  ref.invalidate(journalEntriesProvider);
});

final analyseJournalEntryProvider =
    FutureProvider.family<JournalAnalysis, String>((ref, entryId) async {
      final analysis = await ref
          .read(reflectionJournalRepositoryProvider)
          .analyseEntry(entryId);
      ref.invalidate(journalEntryProvider(entryId));
      return analysis;
    });
