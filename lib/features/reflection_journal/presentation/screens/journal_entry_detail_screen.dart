// lib/features/reflection_journal/presentation/screens/journal_entry_detail_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JournalEntryDetailScreen extends ConsumerWidget {
  const JournalEntryDetailScreen({super.key, required this.entryId});

  final String entryId;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'This can\'t be undone. The entry and its reflection will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(deleteJournalEntryProvider(entryId).future);
      if (context.mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final entryAsync = ref.watch(journalEntryProvider(entryId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.pushNamed(
              'journalEntryCompose',
              extra: entryId,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: entryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: ErrorStateWidget(subtitle: 'Error: $error', title: '')),
        data: (entry) {
          final analysisAsync = ref.watch(analyseJournalEntryProvider(entryId));

          return SingleChildScrollView(
            padding: EdgeInsets.all(Spacing.md.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.content, style: textTheme.bodyLarge),
                Gap(Spacing.lg.h),
                analysisAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (analysis) {
                    if (!analysis.isComplete || analysis.observation == null) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding: EdgeInsets.all(Spacing.md.w),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.md.r,
                        ),
                      ),
                      child: Text(
                        analysis.observation!,
                        style: textTheme.bodyMedium,
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
