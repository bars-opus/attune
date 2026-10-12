import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/core/widgets/buttons/app_fab.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../../domain/code_point_limit.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';
import '../widgets/category_editor_sheet.dart';
import 'planning_entry_screen.dart';

/// ISO 4217 code for the device locale; USD when the locale has none.
String _deviceCurrency() {
  final code = NumberFormat.simpleCurrency().currencyName ?? '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(code) ? code : 'USD';
}

enum _Menu { editTemplate, edit, hide, reset, delete }

class PlanningCategoryScreen extends ConsumerStatefulWidget {
  const PlanningCategoryScreen({super.key, required this.relationshipId, required this.category});
  final String relationshipId;
  final PlanningCategory category;

  @override
  ConsumerState<PlanningCategoryScreen> createState() => _PlanningCategoryScreenState();
}

class _PlanningCategoryScreenState extends ConsumerState<PlanningCategoryScreen> {
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
    unawaited(ref.read(planningRepositoryProvider).markCategorySeen(_category.id).catchError((_) {}));
  }

  bool get _isNotes => _category.seedKey == 'notes';

  void _openEntry(String entryId, {bool openEditor = false}) => Navigator.of(context).push(planningRoute(
      PlanningEntryScreen(relationshipId: widget.relationshipId, entryId: entryId, openEditor: openEditor)));

  /// Notes skip the template choice: a blank sheet opens straight into the
  /// editor, and its title comes from the first line on save.
  bool _creatingNote = false;

  Future<void> _newNote() async {
    if (_creatingNote) return; // a double-tap must not make two notes
    _creatingNote = true;
    try {
      final detail = await ref.read(planningRepositoryProvider).createEntry(
          id: const Uuid().v4(), categoryId: _category.id, title: planningNewNoteTitle,
          useTemplate: true, currency: _deviceCurrency());
      ref.invalidate(planningEntriesProvider(_open));
      if (mounted) _openEntry(detail.entry.id, openEditor: true);
    } catch (e) {
      if (mounted) showPlanningError(context, e);
    } finally {
      _creatingNote = false;
    }
  }

  Future<void> _newEntry() async {
    final draft = await showModalBottomSheet<({String title, bool useTemplate})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewEntrySheet(),
    );
    if (draft == null || !mounted) return;
    try {
      final detail = await ref.read(planningRepositoryProvider).createEntry(
          id: const Uuid().v4(), categoryId: _category.id, title: draft.title,
          useTemplate: draft.useTemplate, currency: _deviceCurrency());
      ref.invalidate(planningEntriesProvider(_open));
      if (mounted) _openEntry(detail.entry.id);
    } catch (e) {
      if (mounted) showPlanningError(context, e);
    }
  }

  Future<void> _menu(_Menu action) async {
    final repo = ref.read(planningRepositoryProvider);
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
          final ok = await planningConfirm(context,
              title: 'Reset the template?',
              message: 'New plans will start from Attune\'s version. Plans you already made are not changed.',
              confirmText: 'Reset');
          if (ok) await repo.resetTemplate(_category.id);
        case _Menu.delete:
          final n = _category.entryCount;
          final ok = await planningConfirm(context,
              title: 'Delete ${_category.name} and its $n ${n == 1 ? 'plan' : 'plans'}?',
              message: 'You can ask support to restore it within 30 days.',
              confirmText: 'Delete',
              destructive: true);
          if (!ok) return;
          await repo.deleteCategory(_category.id);
          if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showPlanningError(context, e);
    } finally {
      ref.invalidate(planningHomeProvider(widget.relationshipId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(planningEntriesProvider(_open));
    return Scaffold(
      appBar: AppBar(
        title: Text(_category.name),
        actions: [
          PopupMenuButton<_Menu>(
            tooltip: 'Category options',
            onSelected: _menu,
            itemBuilder: (_) => [
              if (_category.templateEntryId != null && !_isNotes)
                const PopupMenuItem(value: _Menu.editTemplate, child: Text('Edit template')),
              const PopupMenuItem(value: _Menu.edit, child: Text('Rename or restyle')),
              PopupMenuItem(value: _Menu.hide, child: Text(_category.hidden ? 'Show on Planning' : 'Hide')),
              if (_category.isStarter && !_isNotes)
                const PopupMenuItem(value: _Menu.reset, child: Text('Reset template')),
              if (!_category.isStarter) const PopupMenuItem(value: _Menu.delete, child: Text('Delete category')),
            ],
          ),
        ],
      ),
      floatingActionButton: AppFab(
        heroTag: 'planning-new-plan',
        onPressed: _isNotes ? _newNote : _newEntry,
        icon: Icons.add_rounded,
        label: _isNotes ? 'New note' : 'New plan',
      ),
      body: open.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PlanningErrorState(error: e, onRetry: () => ref.invalidate(planningEntriesProvider(_open))),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(planningEntriesProvider(_open).future),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 400) {
                unawaited(ref.read(planningEntriesProvider(_open).notifier).loadMore());
              }
              return false;
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: Spacing.xxl * 2),
              children: [
                if (s.entries.isEmpty && s.pinned.isEmpty)
                  PlanningEmptyState(
                    icon: planningIcon(_category.icon),
                    message: _isNotes ? 'No notes yet' : 'No plans here yet',
                    actionLabel: _isNotes ? 'Write one' : 'Start one',
                    onAction: _isNotes ? _newNote : _newEntry,
                  ),
                ..._entryTiles(s, _open, _openEntry),
                if (s.loadingMore) const Padding(padding: Spacing.allMd, child: Center(child: CircularProgressIndicator())),
                if (s.loadMoreFailed)
                  TextButton(
                    onPressed: () => ref.read(planningEntriesProvider(_open).notifier).loadMore(),
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
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(planningEntriesProvider(args)).when(
        skipLoadingOnReload: true,
        loading: () => const Padding(padding: Spacing.allMd, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => PlanningErrorState(error: e, onRetry: () => ref.invalidate(planningEntriesProvider(args))),
        data: (s) => Column(children: [
          if (s.entries.isEmpty && s.pinned.isEmpty)
            const Padding(padding: Spacing.allMd, child: Text('Nothing finished yet')),
          ..._entryTiles(s, args, onOpen),
        ]),
      );
}

/// Pinned plans first under a "Pinned" header, then the rest.
List<Widget> _entryTiles(PlanningEntriesState s, PlanningEntriesArgs args, void Function(String) onOpen) => [
      if (s.pinned.isNotEmpty) const _PinnedHeader(),
      for (final e in s.pinned) _EntryTile(entry: e, args: args, onTap: () => onOpen(e.id)),
      for (final e in s.entries) _EntryTile(entry: e, args: args, onTap: () => onOpen(e.id)),
    ];

class _PinnedHeader extends StatelessWidget {
  const _PinnedHeader();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
        child: Row(children: [
          Icon(Icons.push_pin_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: Spacing.xs),
          Text('Pinned', style: Theme.of(context).textTheme.labelLarge),
        ]),
      );
}

enum _EntryAction { pin, delete }

/// One plan in a category. Swipe RIGHT deletes (with Undo); swipe LEFT pins
/// or unpins and leaves the plan on screen. Long-press and screen-reader
/// actions offer the same two choices, since swipes are neither
/// discoverable nor available to assistive technology.
class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.args, required this.onTap});
  final PlanningEntrySummary entry;
  final PlanningEntriesArgs args;
  final VoidCallback onTap;

  String get _pinLabel => entry.pinned ? 'Unpin' : 'Pin';

  Future<void> _togglePin(BuildContext context, WidgetRef ref) async {
    final ctl = ref.read(planningEntriesProvider(args).notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ctl.togglePin(entry);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(planningErrorMessage(mapPlanningError(e)))));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ctl = ref.read(planningEntriesProvider(args).notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ctl.delete(entry);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(planningErrorMessage(mapPlanningError(e)))));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text('Deleted ${entry.title}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          try {
            await ctl.restore(entry.id);
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text(planningErrorMessage(mapPlanningError(e)))));
          }
        },
      ),
    ));
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<_EntryAction>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(entry.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            title: Text(_pinLabel),
            onTap: () => Navigator.pop(c, _EntryAction.pin),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Theme.of(c).colorScheme.error),
            title: const Text('Delete'),
            onTap: () => Navigator.pop(c, _EntryAction.delete),
          ),
        ]),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _EntryAction.pin:
        await _togglePin(context, ref);
      case _EntryAction.delete:
        await _delete(context, ref);
    }
  }

  Widget _swipeBackground(BuildContext context, {required bool delete}) {
    final scheme = Theme.of(context).colorScheme;
    final bg = delete ? scheme.errorContainer : scheme.primaryContainer;
    final fg = delete ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    return Container(
      margin: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.sm),
      padding: Spacing.horizontalMd,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadiusTokens.mdAll),
      alignment: delete ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(delete ? Icons.delete_outline_rounded : (entry.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            color: fg),
        const SizedBox(width: Spacing.xs),
        Text(delete ? 'Delete' : _pinLabel, style: TextStyle(color: fg)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = [
      if (entry.dateStart != null) formatPlanningRange(entry.dateStart, entry.dateEnd),
      if (entry.checklistTotal > 0) '${entry.checklistDone} of ${entry.checklistTotal} done',
    ];
    final text = Theme.of(context).textTheme;
    return Dismissible(
      key: ValueKey('entry-${entry.id}'),
      background: _swipeBackground(context, delete: true), // swipe right
      secondaryBackground: _swipeBackground(context, delete: false), // swipe left
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          await _togglePin(context, ref);
          return false; // pinning keeps the plan on screen
        }
        return true;
      },
      onDismissed: (_) => _delete(context, ref),
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: _pinLabel): () => _togglePin(context, ref),
          const CustomSemanticsAction(label: 'Delete'): () => _delete(context, ref),
        },
        child: GestureDetector(
          onLongPress: () => _menu(context, ref),
          child: CardInkWell(
            onTap: onTap,
            margin: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.sm),
            padding: Spacing.allMd,
            child: Row(children: [
              if (entry.pinned) ...[
                Icon(Icons.push_pin_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: Spacing.sm),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                  if (parts.isNotEmpty) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(parts.join(' · '),
                        style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
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
            inputFormatters: [CodePointLengthFormatter(120)],
            buildCounter: codePointCounter(_title, 120),
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
