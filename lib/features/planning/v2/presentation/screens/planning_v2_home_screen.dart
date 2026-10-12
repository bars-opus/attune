import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';
import '../widgets/category_editor_sheet.dart';
import 'planning_v2_category_screen.dart';

class PlanningV2HomeScreen extends ConsumerStatefulWidget {
  const PlanningV2HomeScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<PlanningV2HomeScreen> createState() => _PlanningV2HomeScreenState();
}

class _PlanningV2HomeScreenState extends ConsumerState<PlanningV2HomeScreen> {
  bool _showHidden = false;

  void _refresh() => ref.invalidate(planningV2HomeProvider(widget.relationshipId));

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e);
    } finally {
      _refresh();
    }
  }

  Future<void> _create() async {
    final draft = await showCategoryEditorSheet(context);
    if (draft == null || !mounted) return;
    await _run(() => ref.read(planningV2RepositoryProvider).createCategory(
        id: const Uuid().v4(), relationshipId: widget.relationshipId,
        name: draft.name, icon: draft.icon, color: draft.color));
  }

  Future<void> _move(List<PlanningCategory> visible, int from, int to) async {
    final list = [...visible];
    final moving = list.removeAt(from);
    list.insert(to, moving);
    await _run(() => ref.read(planningV2RepositoryProvider)
        .moveCategory(moving.id, afterId: to == 0 ? null : list[to - 1].id));
  }

  void _open(PlanningCategory c) => Navigator.of(context).push(
      planningV2Route(PlanningV2CategoryScreen(relationshipId: widget.relationshipId, category: c)));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(planningV2HomeProvider(widget.relationshipId));
    return Scaffold(
      appBar: AppBar(title: const Text('Planning')),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PlanningV2ErrorState(error: e, onRetry: _refresh),
        data: (cats) {
          final visible = [for (final c in cats) if (!c.hidden) c];
          final hidden = [for (final c in cats) if (c.hidden) c];
          return RefreshIndicator(
            onRefresh: () => ref.refresh(planningV2HomeProvider(widget.relationshipId).future),
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              itemCount: visible.length,
              onReorder: (from, to) => _move(visible, from, to > from ? to - 1 : to),
              itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                key: ValueKey(visible[i].id),
                index: i,
                child: _CategoryTile(
                  category: visible[i],
                  onOpen: () => _open(visible[i]),
                  onMoveUp: i == 0 ? null : () => _move(visible, i, i - 1),
                  onMoveDown: i == visible.length - 1 ? null : () => _move(visible, i, i + 1),
                  onHide: () => _run(() => ref.read(planningV2RepositoryProvider)
                      .setCategoryHidden(visible[i].id, hidden: true)),
                ),
              ),
              footer: Column(children: [
                if (hidden.isNotEmpty) ...[
                  ListTile(
                    minTileHeight: 56,
                    leading: Icon(_showHidden ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    title: Text('Hidden (${hidden.length})'),
                    onTap: () => setState(() => _showHidden = !_showHidden),
                  ),
                  if (_showHidden)
                    for (final c in hidden)
                      _CategoryTile(
                        category: c,
                        onOpen: () => _open(c),
                        onUnhide: () => _run(() =>
                            ref.read(planningV2RepositoryProvider).setCategoryHidden(c.id, hidden: false)),
                      ),
                ],
                ListTile(
                  minTileHeight: 56,
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('New category'),
                  onTap: _create,
                ),
                const SizedBox(height: Spacing.xl),
              ]),
            ),
          );
        },
      ),
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
    final tone = planningV2Tone(context, category.color);
    final n = category.entryCount;
    return ListTile(
      minTileHeight: 64,
      leading: CircleAvatar(
        backgroundColor: tone.container,
        child: Icon(planningV2Icon(category.icon), color: tone.onContainer),
      ),
      title: Text(category.name),
      subtitle: Text(n == 1 ? '1 plan' : '$n plans'),
      onTap: onOpen,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (category.hasNew) const PlanningV2NewDot(),
        PopupMenuButton<_CategoryAction>(
          tooltip: 'More for ${category.name}',
          onSelected: (a) => switch (a) {
            _CategoryAction.open => onOpen(),
            _CategoryAction.up => onMoveUp?.call(),
            _CategoryAction.down => onMoveDown?.call(),
            _CategoryAction.hide => onHide?.call(),
            _CategoryAction.unhide => onUnhide?.call(),
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: _CategoryAction.open, child: Text('Open')),
            if (onMoveUp != null) const PopupMenuItem(value: _CategoryAction.up, child: Text('Move up')),
            if (onMoveDown != null) const PopupMenuItem(value: _CategoryAction.down, child: Text('Move down')),
            if (onHide != null) const PopupMenuItem(value: _CategoryAction.hide, child: Text('Hide')),
            if (onUnhide != null) const PopupMenuItem(value: _CategoryAction.unhide, child: Text('Show again')),
          ],
        ),
      ]),
    );
  }
}
