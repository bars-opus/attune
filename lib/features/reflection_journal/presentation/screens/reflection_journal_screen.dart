// lib/features/reflection_journal/presentation/screens/reflection_journal_screen.dart
import 'package:attune/app/documentations/user_manual/data/reflection_journal_docs.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/notes/note_date_sections.dart';
import 'package:attune/core/notes/note_section.dart';
import 'package:attune/features/planning/presentation/widgets/planning_skeletons.dart';
import 'package:attune/features/reflection_journal/data/journal_prompts.dart';
import 'package:attune/features/reflection_journal/data/models/journal_note.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_entry_row.dart';
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
    final docs = ReflectionJournalDocs();

    final tabs = [
      AppTabItem(label: 'Entries', icon: Icons.edit, content: _EntriesTab()),
      AppTabItem(
        label: 'Patterns',
        icon: Icons.pattern,
        content: _PatternsTab(),
      ),
    ];

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        centerTitle: false,
        automaticallyImplyLeading: true,
        backgroundColor: Colors.transparent,
        title: Text(
          'Personal reflection journal',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        actions: [
          AppIconButton(
            icon: Icons.notes_rounded,
            tooltip: 'Tags',
            onPressed: () {
              BottomSheetUtils.showDocumentationBottomSheet(
                context: context,
                showButtons: false,
                widget: DocumentationTabView(
                  module: docs,
                  showDocumentationFirst: true,
                ),
              );
            },
          ),
        ],
      ),
      body: TabsWithContent(
        tabs: tabs,
        initialIndex: 0,
        scrollable: false,
        showContent: true,
      ),
      floatingActionButton: Tooltip(
        message: 'New entry',
        child: AppFab(
          icon: Icons.edit_outlined,
          heroTag: 'journal-new',
          onPressed: () => openNewJournalEntry(context, ref),
        ),
      ),
    );
  }
}

/// Creates an entry and opens it, ready to write. The list refreshes when
/// it closes (an empty one is discarded there).
Future<void> openNewJournalEntry(BuildContext context, WidgetRef ref) async {
  final prompt = randomJournalPrompt();
  try {
    final d = await ref.read(reflectionJournalRepositoryProvider).createEntryV2(promptUsed: prompt);
    if (!context.mounted) return;
    await context.pushNamed('journalEntry', extra: JournalEntryArgs(entryId: d.entry.id, isNew: true, prompt: prompt));
    await ref.read(journalListProvider.notifier).refresh();
  } catch (_) {
    if (context.mounted) context.showErrorSnackbar("Couldn't start a new entry. Please try again.");
  }
}

class _EntriesTab extends ConsumerWidget {
  const _EntriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(journalListProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const PlanningEntriesSkeleton(label: 'Loading entries'),
      error: (error, _) => Center(
        child: ErrorStateWidget(
          title: 'Something went wrong',
          subtitle: "We couldn't load your entries right now.",
          primaryActionLabel: 'Try again',
          onPrimaryAction: () => ref.invalidate(journalListProvider),
        ),
      ),
      data: (s) {
        if (s.pinned.isEmpty && s.entries.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.book_outlined,
            title: 'Your journal is empty',
            subtitle: "Write your first entry whenever you're ready. Nothing here is ever shared with anyone.",
            actionLabel: 'Write an entry',
            onAction: () => openNewJournalEntry(context, ref),
          );
        }
        final now = DateTime.now();
        Future<void> open(String id) async {
          await context.pushNamed('journalEntry', extra: JournalEntryArgs(entryId: id));
          await ref.read(journalListProvider.notifier).refresh();
        }

        Widget section(String title, List<JournalEntrySummary> rows) => NoteSection(
          title: title,
          children: [
            for (var i = 0; i < rows.length; i++)
              JournalEntryRow(entry: rows[i], now: now, last: i == rows.length - 1, onTap: () => open(rows[i].id)),
          ],
        );
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 400) ref.read(journalListProvider.notifier).loadMore();
            return false;
          },
          child: RefreshIndicator(
            onRefresh: () => ref.read(journalListProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (s.pinned.isNotEmpty) section('Pinned', s.pinned),
                for (final g in noteDateSections(s.entries, (e) => e.createdAt, now)) section(g.title, g.items),
              ],
            ),
          ),
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
            icon: Icons.pattern,
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
