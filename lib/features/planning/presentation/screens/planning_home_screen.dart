import 'package:attune/core/widgets/app_content_width.dart';
import 'dart:async';

import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/app_tabs.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/couple_map/presentation/screens/couple_map_screen.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/together/presentation/screens/together_screen.dart';
import 'package:attune/home/widgets/tabs_with_content.dart';
import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/data/couples_journal_docs.dart';
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

/// Planning's tabs, in order (the Map tab exists only with the flag on).
enum PlanningHomeTab { planning, calendar, map }

/// `?tab=` from a link: anything unknown opens Planning's first tab.
PlanningHomeTab planningTabFromQuery(String? value) =>
    PlanningHomeTab.values.asNameMap()[value] ?? PlanningHomeTab.planning;

class PlanningHomeScreen extends ConsumerStatefulWidget {
  const PlanningHomeScreen({
    super.key,
    required this.relationshipId,
    this.initialTab = PlanningHomeTab.planning,
  });
  final String relationshipId;

  /// Where to open: the distance widget opens Map (widget spec §6.5).
  final PlanningHomeTab initialTab;

  @override
  ConsumerState<PlanningHomeScreen> createState() => _PlanningHomeScreenState();
}

class _PlanningHomeScreenState extends ConsumerState<PlanningHomeScreen> {
  bool _showHidden = false;
  bool _openedInitialTab = false;

  /// Each controller TabsWithContent hands over (a new one when the Map tab
  /// appears with the flag): watch it for Map, then honour [initialTab].
  void _onController(TabController controller) {
    controller.addListener(() => _onTabSettled(controller));
    _openInitialTab(controller);
  }

  /// Where to come back to when the map closes.
  int _lastPageIndex = 0;
  bool _openingMap = false;

  /// The Map tab is a door, not a page (owner, 2026-10-16): when the tabs
  /// settle on it, by swipe or tap, the map opens full screen and the tabs
  /// snap back underneath to where they were. A half swipe that bounces
  /// back never settles there, so it opens nothing.
  void _onTabSettled(TabController controller) {
    if (controller.indexIsChanging) return;
    final mapIndex = PlanningHomeTab.map.index;
    if (controller.index != mapIndex) {
      _lastPageIndex = controller.index;
      return;
    }
    if (controller.length <= mapIndex || _openingMap) return;
    _openingMap = true;
    final back = _lastPageIndex;
    final open = openCoupleMap(context, widget.relationshipId);
    // Next frame, once a swipe's scroll has finished: TabBarView ignores an
    // instant index jump while its page is still settling (the underline
    // moved but the page stayed on Map). A 1 ms animation it does follow,
    // hidden under the map sliding in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.animateTo(back, duration: const Duration(milliseconds: 1));
    });
    unawaited(open.whenComplete(() => _openingMap = false));
  }

  /// The Map tab appears once the flag loads, so this waits for a
  /// controller that has it (TabsWithContent hands over each new one). Map
  /// opens full screen over the journal, once.
  void _openInitialTab(TabController controller) {
    if (_openedInitialTab) return;
    final index = widget.initialTab.index;
    if (index == 0) {
      _openedInitialTab = true;
      return;
    }
    if (index < controller.length) {
      _openedInitialTab = true;
      if (widget.initialTab == PlanningHomeTab.map) {
        unawaited(openCoupleMap(context, widget.relationshipId));
      } else {
        controller.index = index;
      }
    }
  }


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
    // Planning, the couple's Together calendar (embedded, so it has no app
    // bar of its own), and — behind couple_map_enabled — the couple map.
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // The journal's guide; Planning's own page is under its Related tab.
    final docs = CouplesJournalDocs();
    final mapEnabled = ref.watch(coupleMapEnabledProvider).valueOrNull ?? false;

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
            tooltip: 'About the couples journal',
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
          if (mapEnabled)
            AppTabItem(
              label: 'Map',
              icon: Icons.map_outlined,
              // Seen only mid-swipe: the map opens as the swipe settles.
              content: const _MapPeek(),
            ),
        ],
        initialIndex: 0,
        onControllerCreated: _onController,
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
            padding: AppContentWidth.padded(
              context,
              const EdgeInsets.symmetric(
                vertical: Spacing.sm,
                horizontal: Spacing.md,
              ),
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
                // What both partners should know about a shared journal.
                SemanticContainerWidget(
                  title: 'Shared by both of you',
                  content:
                      'Everything here is shared: either of you can add, edit or delete any plan, and you both see every change. For thoughts just for you, use your Reflection Journal — only you can see it.',
                  icon: Icons.people_outline,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                  borderColor: colorScheme.primary,
                  iconColor: colorScheme.primary,
                  textTheme: Theme.of(context).textTheme,
                ),
                const Gap(Spacing.md),
                SemanticContainerWidget(
                  title: 'Done with a plan?',
                  content:
                      'Mark it done, or choose "Put away gently" in its menu to archive it quietly — no one is notified, its reminders stop, and Reopen brings it back.',
                  icon: Icons.lightbulb_outline,
                  backgroundColor: colorScheme.success.withValues(alpha: 0.1),
                  borderColor: colorScheme.success,
                  iconColor: colorScheme.success,
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
        // No Hero here (owner, 2026-10-16): with Recent at the top, the name
        // flying into the category screen looked wrong.
        title: category.name,
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

/// What a swipe towards Map reveals before the map opens: never a blank page.
class _MapPeek extends StatelessWidget {
  const _MapPeek();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 40, color: muted),
            const SizedBox(height: Spacing.sm),
            Text(
              'Opening the map…',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
