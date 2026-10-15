import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/app_tabs.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/together/presentation/screens/together_screen.dart';
import 'package:attune/home/widgets/tabs_with_content.dart';
import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/data/reflection_journal_docs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/planning_models.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';
import '../widgets/category_editor_sheet.dart';
import '../widgets/planning_skeletons.dart';
import '../widgets/planning_recent.dart';
import 'planning_category_screen.dart';
import 'planning_recent_screen.dart';

class PlanningHomeScreen extends ConsumerStatefulWidget {
  const PlanningHomeScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<PlanningHomeScreen> createState() => _PlanningHomeScreenState();
}

class _PlanningHomeScreenState extends ConsumerState<PlanningHomeScreen> {
  bool _showHidden = false;

  @override
  void initState() {
    super.initState();
    _reportTimezone();
  }

  /// Countdown pushes arrive at 08:00 in this zone. Best effort: a zone the
  /// server doesn't know (or no network) leaves the last one, else UTC.
  Future<void> _reportTimezone() async {
    try {
      final tz = await ref.read(planningDeviceTimezoneProvider.future);
      if (tz == null || !mounted) return;
      await ref
          .read(planningRepositoryProvider)
          .setTimezone(widget.relationshipId, tz);
    } catch (_) {}
  }

  void _refresh() =>
      ref.invalidate(planningHomeProvider(widget.relationshipId));

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showPlanningError(context, e);
    } finally {
      _refresh();
    }
  }

  Future<void> _create() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewCategoryChooser(),
    );
    if (choice == null || !mounted) return;
    if (choice != _blankCategory) {
      return _run(
        () => ref
            .read(planningRepositoryProvider)
            .createCategoryFromGallery(
              id: const Uuid().v4(),
              relationshipId: widget.relationshipId,
              key: choice,
            ),
      );
    }
    final draft = await showCategoryEditorSheet(context);
    if (draft == null || !mounted) return;
    await _run(
      () => ref
          .read(planningRepositoryProvider)
          .createCategory(
            id: const Uuid().v4(),
            relationshipId: widget.relationshipId,
            name: draft.name,
            icon: draft.icon,
            color: draft.color,
          ),
    );
  }

  Future<void> _move(List<PlanningCategory> visible, int from, int to) async {
    final list = [...visible];
    final moving = list.removeAt(from);
    list.insert(to, moving);
    await _run(
      () => ref
          .read(planningRepositoryProvider)
          .moveCategory(moving.id, afterId: to == 0 ? null : list[to - 1].id),
    );
  }

  void _open(PlanningCategory c) => Navigator.of(context).push(
    planningRoute(
      PlanningCategoryScreen(
        relationshipId: widget.relationshipId,
        category: c,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Two tabs: the categories, and the couple's Together hub (embedded, so
    // it has no app bar of its own under this screen's).
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final docs = ReflectionJournalDocs();

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        // The couple's journal, by their chosen name ("Couples journal"
        // until they choose one).
        title: Text(
          coupleJournalTitle(
            ref.watch(coupleNameProvider(widget.relationshipId)).valueOrNull,
          ),
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
        tabs: [
          AppTabItem(
            label: 'Planning',
            icon: Icons.checklist_rounded,
            content: _categories(context),
          ),
          const AppTabItem(
            label: 'Calendar',
            icon: Icons.calendar_month_rounded,
            // The couple's Together hub (Together plan 1b R1).
            content: TogetherScreen(embedded: true),
          ),
        ],
        initialIndex: 0,
        scrollable: false,
        showContent: true,
        // Switching back to a tab shows it as it was (no reload); its data
        // keeps refreshing from change signals while it's hidden.
        keepTabsAlive: true,
      ),
    );
  }

  Widget _categories(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final async = ref.watch(planningHomeProvider(widget.relationshipId));
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const PlanningCategoriesSkeleton(),
      error: (e, _) => PlanningErrorState(error: e, onRetry: _refresh),
      data: (cats) {
        final visible = [
          for (final c in cats)
            if (!c.hidden) c,
        ];
        final hidden = [
          for (final c in cats)
            if (c.hidden) c,
        ];
        return RefreshIndicator(
          onRefresh: () {
            ref.invalidate(planningRecentProvider(widget.relationshipId));
            return ref.refresh(
              planningHomeProvider(widget.relationshipId).future,
            );
          },
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            // What they were just working on, across every category, first.
            header: PlanningRecentSection(
              relationshipId: widget.relationshipId,
              onSeeAll:
                  () => Navigator.of(context).push(
                    planningRoute(
                      PlanningRecentScreen(
                        relationshipId: widget.relationshipId,
                      ),
                    ),
                  ),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: Spacing.sm,
              horizontal: Spacing.md,
            ),
            itemCount: visible.length,
            onReorder:
                (from, to) => _move(visible, from, to > from ? to - 1 : to),
            itemBuilder:
                (context, i) => ReorderableDelayedDragStartListener(
                  key: ValueKey(visible[i].id),
                  index: i,
                  child: _CategoryTile(
                    category: visible[i],
                    onOpen: () => _open(visible[i]),
                    onMoveUp: i == 0 ? null : () => _move(visible, i, i - 1),
                    onMoveDown:
                        i == visible.length - 1
                            ? null
                            : () => _move(visible, i, i + 1),
                    onHide:
                        () => _run(
                          () => ref
                              .read(planningRepositoryProvider)
                              .setCategoryHidden(visible[i].id, hidden: true),
                        ),
                  ),
                ),
            footer: Column(
              children: [
                if (hidden.isNotEmpty) ...[
                  InfoRowWidget(
                    padding: _rowPadding,
                    icon:
                        _showHidden
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                    title: 'Hidden (${hidden.length})',
                    subtitle: '',
                    showDivider: false,
                    disableTrailing: true,
                    onTap: () => setState(() => _showHidden = !_showHidden),
                  ),
                  if (_showHidden)
                    for (final c in hidden)
                      _CategoryTile(
                        category: c,
                        onOpen: () => _open(c),
                        onUnhide:
                            () => _run(
                              () => ref
                                  .read(planningRepositoryProvider)
                                  .setCategoryHidden(c.id, hidden: false),
                            ),
                      ),
                ],
                Gap(Spacing.lg),
                InfoRowWidget(
                  padding: _rowPadding,
                  icon: Icons.add_rounded,
                  title: 'New category',
                  subtitle: '',
                  showDivider: false,
                  disableTrailing: true,
                  onTap: _create,
                ),
                const Gap(Spacing.xl),
                SemanticContainerWidget(
                  content:
                      'Unlike your personal refelction jounral, this journal is shared between both couples, either can add contents, modify, and delete. Both couples can see and modify this journal.',
                  icon: Icons.info,
                  title: '',
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                  borderColor: colorScheme.primary,
                  iconColor: colorScheme.primary,
                  textTheme: Theme.of(context).textTheme,
                ),
                const Gap(Spacing.xl),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _CategoryAction { open, up, down, hide, unhide }

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onOpen,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.onUnhide,
  });

  final PlanningCategory category;
  final VoidCallback onOpen;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final VoidCallback? onUnhide;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final n = category.entryCount;
    return CardInkWell(
      padding: const EdgeInsets.all(Spacing.sm),
      margin: EdgeInsets.only(bottom: .5.h),
      elevation: ElevationTokens.xs,
      child: InfoRowWidget(
        padding: _rowPadding,
        icon: planningIcon(category.icon),
        iconColor: colorScheme.background,
        backgroundColor: planningCategoryFill(context, category.color),
        title: category.name,
        titleBuilder:
            (title) => PlanningCategoryHero(
              categoryId: category.id,
              title: title as Text,
            ),
        subtitle: n == 1 ? '1 plan' : '$n plans',
        showDivider: false,
        onTap: onOpen,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category.hasNew) const PlanningNewDot(),
            PopupMenuButton<_CategoryAction>(
              tooltip: 'More for ${category.name}',
              onSelected:
                  (a) => switch (a) {
                    _CategoryAction.open => onOpen(),
                    _CategoryAction.up => onMoveUp?.call(),
                    _CategoryAction.down => onMoveDown?.call(),
                    _CategoryAction.hide => onHide?.call(),
                    _CategoryAction.unhide => onUnhide?.call(),
                  },
              itemBuilder:
                  (_) => [
                    const PopupMenuItem(
                      value: _CategoryAction.open,
                      child: Text('Open'),
                    ),
                    if (onMoveUp != null)
                      const PopupMenuItem(
                        value: _CategoryAction.up,
                        child: Text('Move up'),
                      ),
                    if (onMoveDown != null)
                      const PopupMenuItem(
                        value: _CategoryAction.down,
                        child: Text('Move down'),
                      ),
                    if (onHide != null)
                      const PopupMenuItem(
                        value: _CategoryAction.hide,
                        child: Text('Hide'),
                      ),
                    if (onUnhide != null)
                      const PopupMenuItem(
                        value: _CategoryAction.unhide,
                        child: Text('Show again'),
                      ),
                  ],
            ),
          ],
        ),
      ),
    );
  }
}

const _blankCategory = '';

/// Category rows are the app's InfoRowWidget; this is their list inset.
const _rowPadding = EdgeInsets.symmetric(
  horizontal: Spacing.md,
  vertical: Spacing.sm,
);

/// "+ New category": start blank, or from one of the server's gallery ideas.
class _NewCategoryChooser extends ConsumerWidget {
  const _NewCategoryChooser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gallery = ref.watch(planningGalleryProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: Spacing.md),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                0,
                Spacing.md,
                Spacing.sm,
              ),
              child: Text('New category', style: theme.textTheme.titleLarge),
            ),
            InfoRowWidget(
              padding: _rowPadding,
              icon: Icons.add_rounded,
              title: 'Blank category',
              subtitle: 'Name it and build its template yourself',
              showDivider: false,
              showTrailingArrow: true,
              onTap: () => Navigator.pop(context, _blankCategory),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.xs,
              ),
              child: Text(
                'Start from an idea',
                style: theme.textTheme.labelLarge,
              ),
            ),
            ...gallery.when(
              loading:
                  () => [
                    const Padding(
                      padding: Spacing.allMd,
                      child: LinearProgressIndicator(),
                    ),
                  ],
              error:
                  (_, __) => [
                    const Padding(
                      padding: _rowPadding,
                      child: Text(
                        "Ideas couldn't load. You can still start a blank category.",
                      ),
                    ),
                  ],
              data:
                  (ideas) => [
                    for (final g in ideas)
                      InfoRowWidget(
                        padding: _rowPadding,
                        icon: planningIcon(g.icon),
                        iconColor:
                            Theme.of(context)
                                .colorScheme
                                .background, // ignore: deprecated_member_use
                        backgroundColor: planningCategoryFill(context, g.color),
                        title: g.name,
                        subtitle: g.description,
                        showDivider: false,
                        showTrailingArrow: true,
                        onTap: () => Navigator.pop(context, g.key),
                      ),
                  ],
            ),
          ],
        ),
      ),
    );
  }
}
