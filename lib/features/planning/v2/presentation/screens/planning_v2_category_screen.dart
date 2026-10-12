import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/core/widgets/buttons/app_fab.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';
import '../widgets/category_editor_sheet.dart';
import 'planning_v2_entry_screen.dart';

/// ISO 4217 code for the device locale; USD when the locale has none.
String _deviceCurrency() {
  final code = NumberFormat.simpleCurrency().currencyName ?? '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(code) ? code : 'USD';
}

enum _Menu { editTemplate, edit, hide, reset, delete }

class PlanningV2CategoryScreen extends ConsumerStatefulWidget {
  const PlanningV2CategoryScreen({super.key, required this.relationshipId, required this.category});
  final String relationshipId;
  final PlanningCategory category;

  @override
  ConsumerState<PlanningV2CategoryScreen> createState() => _PlanningV2CategoryScreenState();
}

class _PlanningV2CategoryScreenState extends ConsumerState<PlanningV2CategoryScreen> {
  late PlanningCategory _category = widget.category;
  bool _showClosed = false;

  PlanningEntriesArgs get _open =>
      (relationshipId: widget.relationshipId, categoryId: _category.id, group: 'open');
  PlanningEntriesArgs get _closed =>
      (relationshipId: widget.relationshipId, categoryId: _category.id, group: 'closed');

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: a failed "seen" write only leaves the dot showing.
    unawaited(ref.read(planningV2RepositoryProvider).markCategorySeen(_category.id).catchError((_) {}));
  }

  void _openEntry(String entryId) => Navigator.of(context).push(
      planningV2Route(PlanningV2EntryScreen(relationshipId: widget.relationshipId, entryId: entryId)));

  Future<void> _newEntry() async {
    final draft = await showModalBottomSheet<({String title, bool useTemplate})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewEntrySheet(),
    );
    if (draft == null || !mounted) return;
    try {
      final detail = await ref.read(planningV2RepositoryProvider).createEntry(
          id: const Uuid().v4(), categoryId: _category.id, title: draft.title,
          useTemplate: draft.useTemplate, currency: _deviceCurrency());
      ref.invalidate(planningV2EntriesProvider(_open));
      if (mounted) _openEntry(detail.entry.id);
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e);
    }
  }

  Future<void> _menu(_Menu action) async {
    final repo = ref.read(planningV2RepositoryProvider);
    try {
      switch (action) {
        case _Menu.editTemplate:
          if (_category.templateEntryId != null) _openEntry(_category.templateEntryId!);
        case _Menu.edit:
          final d = await showCategoryEditorSheet(context,
              initial: (name: _category.name, icon: _category.icon, color: _category.color));
          if (d == null) return;
          final updated = await repo.updateCategory(id: _category.id, name: d.name, icon: d.icon, color: d.color);
          setState(() => _category = _category.copyWith(name: updated.name, icon: updated.icon, color: updated.color));
        case _Menu.hide:
          await repo.setCategoryHidden(_category.id, hidden: !_category.hidden);
          setState(() => _category = _category.copyWith(hidden: !_category.hidden));
        case _Menu.reset:
          final ok = await planningV2Confirm(context,
              title: 'Reset the template?',
              message: 'New plans will start from Attune\'s version. Plans you already made are not changed.',
              confirmText: 'Reset');
          if (ok) await repo.resetTemplate(_category.id);
        case _Menu.delete:
          final n = _category.entryCount;
          final ok = await planningV2Confirm(context,
              title: 'Delete ${_category.name} and its $n ${n == 1 ? 'plan' : 'plans'}?',
              message: 'You can ask support to restore it within 30 days.',
              confirmText: 'Delete',
              destructive: true);
          if (!ok) return;
          await repo.deleteCategory(_category.id);
          if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e);
    } finally {
      ref.invalidate(planningV2HomeProvider(widget.relationshipId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(planningV2EntriesProvider(_open));
    return Scaffold(
      appBar: AppBar(
        title: Text(_category.name),
        actions: [
          PopupMenuButton<_Menu>(
            tooltip: 'Category options',
            onSelected: _menu,
            itemBuilder: (_) => [
              if (_category.templateEntryId != null)
                const PopupMenuItem(value: _Menu.editTemplate, child: Text('Edit template')),
              const PopupMenuItem(value: _Menu.edit, child: Text('Rename or restyle')),
              PopupMenuItem(value: _Menu.hide, child: Text(_category.hidden ? 'Show on Planning' : 'Hide')),
              if (_category.isStarter) const PopupMenuItem(value: _Menu.reset, child: Text('Reset template')),
              if (!_category.isStarter) const PopupMenuItem(value: _Menu.delete, child: Text('Delete category')),
            ],
          ),
        ],
      ),
      floatingActionButton: AppFab(
        heroTag: 'planning-v2-new-plan',
        onPressed: _newEntry,
        icon: Icons.add_rounded,
        label: 'New plan',
      ),
      body: open.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PlanningV2ErrorState(error: e, onRetry: () => ref.invalidate(planningV2EntriesProvider(_open))),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(planningV2EntriesProvider(_open).future),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 400) {
                unawaited(ref.read(planningV2EntriesProvider(_open).notifier).loadMore());
              }
              return false;
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: Spacing.xxl * 2),
              children: [
                if (s.entries.isEmpty)
                  PlanningV2EmptyState(
                    icon: planningV2Icon(_category.icon),
                    message: 'No plans here yet',
                    actionLabel: 'Start one',
                    onAction: _newEntry,
                  ),
                for (final e in s.entries) _EntryTile(entry: e, onTap: () => _openEntry(e.id)),
                if (s.loadingMore) const Padding(padding: Spacing.allMd, child: Center(child: CircularProgressIndicator())),
                if (s.loadMoreFailed)
                  TextButton(
                    onPressed: () => ref.read(planningV2EntriesProvider(_open).notifier).loadMore(),
                    child: const Text('Could not load more. Try again'),
                  ),
                ListTile(
                  minTileHeight: 56,
                  leading: Icon(_showClosed ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                  title: const Text('Done & archived'),
                  onTap: () => setState(() => _showClosed = !_showClosed),
                ),
                if (_showClosed) _ClosedEntries(args: _closed, onOpen: _openEntry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClosedEntries extends ConsumerWidget {
  const _ClosedEntries({required this.args, required this.onOpen});
  final PlanningEntriesArgs args;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(planningV2EntriesProvider(args)).when(
        skipLoadingOnReload: true,
        loading: () => const Padding(padding: Spacing.allMd, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => PlanningV2ErrorState(error: e, onRetry: () => ref.invalidate(planningV2EntriesProvider(args))),
        data: (s) => Column(children: [
          if (s.entries.isEmpty) const Padding(padding: Spacing.allMd, child: Text('Nothing finished yet')),
          for (final e in s.entries) _EntryTile(entry: e, onTap: () => onOpen(e.id)),
        ]),
      );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});
  final PlanningEntrySummary entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (entry.dateStart != null) formatPlanningRange(entry.dateStart, entry.dateEnd),
      if (entry.checklistTotal > 0) '${entry.checklistDone} of ${entry.checklistTotal} done',
    ];
    final text = Theme.of(context).textTheme;
    return CardInkWell(
      onTap: onTap,
      margin: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.sm),
      padding: Spacing.allMd,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
            if (parts.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Text(parts.join(' · '), style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ]),
        ),
        const Icon(Icons.chevron_right_rounded),
      ]),
    );
  }
}

class _NewEntrySheet extends StatefulWidget {
  const _NewEntrySheet();

  @override
  State<_NewEntrySheet> createState() => _NewEntrySheetState();
}

class _NewEntrySheetState extends State<_NewEntrySheet> {
  final _title = TextEditingController();
  bool _useTemplate = true;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          left: Spacing.lg, right: Spacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('New plan', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _title,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Spacing.sm),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Use template'), icon: Icon(Icons.auto_awesome_rounded)),
              ButtonSegment(value: false, label: Text('Start blank'), icon: Icon(Icons.note_add_outlined)),
            ],
            selected: {_useTemplate},
            onSelectionChanged: (s) => setState(() => _useTemplate = s.first),
          ),
          const SizedBox(height: Spacing.lg),
          AppButton(
            label: 'Create',
            isDisabled: _title.text.trim().isEmpty,
            onPressed: () => Navigator.of(context).pop((title: _title.text.trim(), useTemplate: _useTemplate)),
          ),
        ]),
      );
}
