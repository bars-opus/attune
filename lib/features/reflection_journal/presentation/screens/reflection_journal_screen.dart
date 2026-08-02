// lib/features/reflection_journal/presentation/screens/reflection_journal_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_entry_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReflectionJournalScreen extends ConsumerStatefulWidget {
  const ReflectionJournalScreen({super.key});

  @override
  ConsumerState<ReflectionJournalScreen> createState() =>
      _ReflectionJournalScreenState();
}

class _ReflectionJournalScreenState
    extends ConsumerState<ReflectionJournalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Reflection journal',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Entries'), Tab(text: 'Patterns')],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.pushNamed('journalEntryCompose');
        },
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Write'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_EntriesTab(), _PatternsTab()],
      ),
    );
  }
}

class _EntriesTab extends ConsumerWidget {
  const _EntriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(journalEntriesProvider);

    return entriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) {
        debugPrint('reflection_journal error: $error');
        return const Center(
          child: ErrorStateWidget(
            title: 'Something went wrong',
            subtitle:
                'We couldn\'t load your entries right now. Please try again in a moment.',
          ),
        );
      },
      data: (entries) {
        if (entries.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.book_outlined,
            title: 'Your journal is empty',
            subtitle:
                'Write your first entry whenever you\'re ready. Nothing here is ever shared with anyone.',
            actionLabel: 'Write an entry',
            onAction: () => context.pushNamed('journalEntryCompose'),
          );
        }

        return ListView.separated(
          padding: EdgeInsets.all(Spacing.md.w),
          itemCount: entries.length,
          separatorBuilder: (_, __) => Gap(Spacing.smMd.h),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return JournalEntryCard(
              entry: entry,
              onTap: () => context.pushNamed(
                'journalEntryDetail',
                extra: entry.id,
              ),
            );
          },
        );
      },
    );
  }
}

class _PatternsTab extends ConsumerWidget {
  const _PatternsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patternsAsync = ref.watch(journalPatternsProvider);
    final textTheme = Theme.of(context).textTheme;

    return patternsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) {
        debugPrint('reflection_journal error: $error');
        return const Center(
          child: ErrorStateWidget(
            title: 'Something went wrong',
            subtitle:
                'We couldn\'t load your patterns right now. Please try again in a moment.',
          ),
        );
      },
      data: (patterns) {
        if (patterns.status == 'insufficient_evidence') {
          return EmptyStateWidget(
            icon: Icons.insights_outlined,
            title: 'Not enough entries yet',
            subtitle:
                'Once you\'ve written a few entries, patterns across them will show up here.',
          );
        }

        return Padding(
          padding: EdgeInsets.all(Spacing.md.w),
          child: Text(patterns.summary ?? '', style: textTheme.bodyMedium),
        );
      },
    );
  }
}
