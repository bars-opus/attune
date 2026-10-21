import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/notes/note_section.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'dart:async';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_fab.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
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
import '../widgets/planning_skeletons.dart';
import 'planning_entry_screen.dart';

/// ISO 4217 code for the device locale; USD when the locale has none.
String _deviceCurrency() {
  final code = NumberFormat.simpleCurrency().currencyName ?? '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(code) ? code : 'USD';
}

enum _Menu { closed, editTemplate, edit, hide, reset, delete }

class PlanningCategoryScreen extends ConsumerStatefulWidget {
  const PlanningCategoryScreen({
    super.key,
    required this.relationshipId,
    required this.category,
  });
  final String relationshipId;
  final PlanningCategory category;

  @override
  ConsumerState<PlanningCategoryScreen> createState() =>
      _PlanningCategoryScreenState();
}

class _PlanningCategoryScreenState
    extends ConsumerState<PlanningCategoryScreen> {
  late PlanningCategory _category = widget.category;

  PlanningEntriesArgs get _open => (
    relationshipId: widget.relationshipId,
    categoryId: _category.id,
    group: 'open',
  );
  PlanningEntriesArgs get _closed => (
    relationshipId: widget.relationshipId,
    categoryId: _category.id,
    group: 'closed',
  );

  // No "seen" write here: the dots are per plan since 2026-10-18, and
  // opening a plan (get_planning_entry) is what clears them.

  bool get _isNotes => _category.seedKey == 'notes';

  void _openEntry(String entryId, {bool openEditor = false}) =>
      Navigator.of(context).push(
        planningRoute(
          PlanningEntryScreen(
            relationshipId: widget.relationshipId,
            entryId: entryId,
            // The title is there from the first frame, so it can fly in.
            categoryId: _category.id,
            categoryName: _category.name,
            openEditor: openEditor,
          ),
        ),
      );

  /// Notes skip the template choice: a blank sheet opens straight into the
  /// editor, and its title comes from the first line on save.
  bool _creatingNote = false;

  Future<void> _newNote() async {
    if (_creatingNote) return; // a double-tap must not make two notes
    _creatingNote = true;
    try {
      final detail = await ref
          .read(planningRepositoryProvider)
          .createEntry(
            id: const Uuid().v4(),
            categoryId: _category.id,
            title: planningNewNoteTitle,
            useTemplate: true,
            currency: _deviceCurrency(),
          );
      ref.invalidate(planningEntriesProvider(_open));
      if (mounted) _openEntry(detail.entry.id, openEditor: true);
    } catch (e) {
      if (mounted) showPlanningError(context, e);
    } finally {
      _creatingNote = false;
    }
  }

  Future<void> _newEntry() async {
    final draft =
        await BottomSheetUtils.showDocumentationBottomSheet<({String title, bool useTemplate})>(
          context: context,
          // Neutral, so the title field stands out against it.
          backgroundColor: Theme.of(context).colorScheme.neutral,
          widget: const _NewEntrySheet(),
        );
    if (draft == null || !mounted) return;
    try {
      final detail = await ref
          .read(planningRepositoryProvider)
          .createEntry(
            id: const Uuid().v4(),
            categoryId: _category.id,
            title: draft.title,
            useTemplate: draft.useTemplate,
            currency: _deviceCurrency(),
          );
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
        case _Menu.closed:
          await Navigator.of(context).push(
            planningRoute(
              _ClosedEntriesScreen(args: _closed, onOpen: _openEntry),
            ),
          );
        case _Menu.editTemplate:
          if (_category.templateEntryId != null)
            _openEntry(_category.templateEntryId!);
        case _Menu.edit:
          final d = await showCategoryEditorSheet(
            context,
            initial: (
              name: _category.name,
              icon: _category.icon,
              color: _category.color,
            ),
          );
          if (d == null) return;
          final updated = await repo.updateCategory(
            id: _category.id,
            name: d.name,
            icon: d.icon,
            color: d.color,
          );
          setState(
            () =>
                _category = _category.copyWith(
                  name: updated.name,
                  icon: updated.icon,
                  color: updated.color,
                ),
          );
        case _Menu.hide:
          await repo.setCategoryHidden(_category.id, hidden: !_category.hidden);
          setState(
            () => _category = _category.copyWith(hidden: !_category.hidden),
          );
        case _Menu.reset:
          final ok = await planningConfirm(
            context,
            title: 'Reset the template?',
            message:
                'New plans will start from Attune\'s version. Plans you already made are not changed.',
            confirmText: 'Reset',
          );
          if (ok) await repo.resetTemplate(_category.id);
        case _Menu.delete:
          final n = _category.entryCount;
          final ok = await planningConfirm(
            context,
            title:
                'Delete ${_category.name} and its $n ${n == 1 ? 'plan' : 'plans'}?',
            message: 'You can ask support to restore it within 30 days.',
            confirmText: 'Delete',
            destructive: true,
          );
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
        centerTitle: false,
        backgroundColor: Colors.transparent,
        title: PlanningCategoryTitle(
          categoryId: _category.id,
          name: _category.name,
          icon: _category.icon,
          color: _category.color,
        ),

        actions: [
          PopupMenuButton<_Menu>(
            tooltip: 'Category options',
            icon: const Icon(
              Icons.more_vert,
            ), // vertical in app bars, on every platform
            onSelected: _menu,
            itemBuilder:
                (_) => [
                  const PopupMenuItem(
                    value: _Menu.closed,
                    child: Text('Done & archived'),
                  ),
                  if (_category.templateEntryId != null && !_isNotes)
                    const PopupMenuItem(
                      value: _Menu.editTemplate,
                      child: Text('Edit template'),
                    ),
                  const PopupMenuItem(
                    value: _Menu.edit,
                    child: Text('Rename or restyle'),
                  ),
                  PopupMenuItem(
                    value: _Menu.hide,
                    child: Text(_category.hidden ? 'Show on Planning' : 'Hide'),
                  ),
                  if (_category.isStarter && !_isNotes)
                    const PopupMenuItem(
                      value: _Menu.reset,
                      child: Text('Reset template'),
                    ),
                  if (!_category.isStarter)
                    const PopupMenuItem(
                      value: _Menu.delete,
                      child: Text('Delete category'),
                    ),
                ],
          ),
        ],
      ),
      floatingActionButton: Tooltip(
        message: _isNotes ? 'New note' : 'New plan',
        child: AppFab(
          heroTag: 'planning-new-plan',
          onPressed: _isNotes ? _newNote : _newEntry,
          icon: Icons.add_rounded,
        ),
      ),
      body: open.when(
        skipLoadingOnReload: true,
        loading:
            () => PlanningEntriesSkeleton(
              label: _isNotes ? 'Loading notes' : 'Loading plans',
            ),
        error:
            (e, _) => PlanningErrorState(
              error: e,
              onRetry: () => ref.invalidate(planningEntriesProvider(_open)),
            ),
        data:
            (s) => RefreshIndicator(
              onRefresh:
                  () => ref.refresh(planningEntriesProvider(_open).future),
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 400) {
                    unawaited(
                      ref
                          .read(planningEntriesProvider(_open).notifier)
                          .loadMore(),
                    );
                  }
                  return false;
                },
                child: ListView(
                  padding: AppContentWidth.padded(
                    context,
                    const EdgeInsets.only(bottom: Spacing.xxl * 2),
                  ),
                  children: [
                    if (s.entries.isEmpty && s.pinned.isEmpty)
                      // The app's empty state, centred in the screen.
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.6,
                        child: Center(
                          child: PlanningEmptyState(
                            icon: planningIcon(_category.icon),
                            message:
                                _isNotes ? 'No notes yet' : 'No plans here yet',
                            detail:
                                _isNotes
                                    ? "Write something down; you'll both see it."
                                    : "Start a plan and you'll both see it here.",
                            actionLabel: _isNotes ? 'Write one' : 'Start one',
                            onAction: _isNotes ? _newNote : _newEntry,
                          ),
                        ),
                      ),
                    ..._entryTiles(s, _open, _openEntry),
                    if (s.loadingMore)
                      const Padding(
                        padding: Spacing.allMd,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (s.loadMoreFailed)
                      TextButton(
                        onPressed:
                            () =>
                                ref
                                    .read(
                                      planningEntriesProvider(_open).notifier,
                                    )
                                    .loadMore(),
                        child: const Text('Could not load more. Try again'),
                      ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

/// Done and archived plans, grouped the same way. Opened from the app bar menu.
class _ClosedEntriesScreen extends ConsumerWidget {
  const _ClosedEntriesScreen({required this.args, required this.onOpen});
  final PlanningEntriesArgs args;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Done & archived')),
    body: ref
        .watch(planningEntriesProvider(args))
        .when(
          skipLoadingOnReload: true,
          loading: () => const PlanningEntriesSkeleton(),
          error:
              (e, _) => PlanningErrorState(
                error: e,
                onRetry: () => ref.invalidate(planningEntriesProvider(args)),
              ),
          data:
              (s) => ListView(
                padding: AppContentWidth.padded(
                  context,
                  const EdgeInsets.only(bottom: Spacing.xxl),
                ),
                children: [
                  if (s.entries.isEmpty && s.pinned.isEmpty)
                    const Padding(
                      padding: Spacing.allMd,
                      child: Center(child: Text('Nothing finished yet')),
                    ),
                  ..._entryTiles(s, args, onOpen),
                ],
              ),
        ),
  );
}

/// Pinned first, then Today, Yesterday, Previous 7 Days and so on — each a
/// titled card of rows, laid out like the Settings screen's sections.
List<Widget> _entryTiles(
  PlanningEntriesState s,
  PlanningEntriesArgs args,
  void Function(String) onOpen,
) {
  final now = DateTime.now();
  Widget section(String title, List<PlanningEntrySummary> entries) => NoteSection(
    title: title,
    children: [
      for (var i = 0; i < entries.length; i++)
        _EntryTile(
          entry: entries[i],
          args: args,
          now: now,
          last: i == entries.length - 1,
          onTap: () => onOpen(entries[i].id),
        ),
    ],
  );
  return [
    if (s.pinned.isNotEmpty) section('Pinned', s.pinned),
    for (final g in planningDateSections(s.entries, now))
      section(g.title, g.entries),
  ];
}

enum _EntryAction { pin, delete }

/// One plan in a category. Swipe RIGHT deletes (with Undo); swipe LEFT pins
/// or unpins and leaves the plan on screen. Long-press and screen-reader
/// actions offer the same two choices, since swipes are neither
/// discoverable nor available to assistive technology.
class _EntryTile extends ConsumerWidget {
  const _EntryTile({
    required this.entry,
    required this.args,
    required this.now,
    required this.last,
    required this.onTap,
  });
  final PlanningEntrySummary entry;
  final PlanningEntriesArgs args;
  final DateTime now;

  /// The last row in its section card: no divider under it.
  final bool last;
  final VoidCallback onTap;

  String get _pinLabel => entry.pinned ? 'Unpin' : 'Pin';

  Future<void> _togglePin(BuildContext context, WidgetRef ref) async {
    final ctl = ref.read(planningEntriesProvider(args).notifier);
    // The screen's context: this row can leave the list while we wait.
    final host = Navigator.of(context).context;
    try {
      await ctl.togglePin(entry);
    } catch (e) {
      host.showErrorSnackbar(planningErrorMessage(mapPlanningError(e)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ctl = ref.read(planningEntriesProvider(args).notifier);
    // The screen's context: this row leaves the list as soon as it's deleted.
    final host = Navigator.of(context).context;
    try {
      await ctl.delete(entry);
    } catch (e) {
      host.showErrorSnackbar(planningErrorMessage(mapPlanningError(e)));
      return;
    }
    host.showInfoSnackbar(
      'Deleted ${entry.title}',
      actionLabel: 'Undo',
      onAction: () async {
        try {
          await ctl.restore(entry.id);
        } catch (e) {
          host.showErrorSnackbar(planningErrorMessage(mapPlanningError(e)));
        }
      },
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<_EntryAction>(
      context: context,
      showDragHandle: true,
      builder:
          (c) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    entry.pinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                  ),
                  title: Text(_pinLabel),
                  onTap: () => Navigator.pop(c, _EntryAction.pin),
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(c).colorScheme.error,
                  ),
                  title: const Text('Delete'),
                  onTap: () => Navigator.pop(c, _EntryAction.delete),
                ),
              ],
            ),
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
      padding: Spacing.horizontalMd,
      color: bg,
      alignment: delete ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            delete
                ? Icons.delete_outline_rounded
                : (entry.pinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded),
            color: fg,
          ),
          const Gap(Spacing.xs),
          Text(delete ? 'Delete' : _pinLabel, style: TextStyle(color: fg)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = [
      planningRowDate(entry.lastActivityAt, now),
      if (entry.dateStart != null)
        formatPlanningRange(entry.dateStart, entry.dateEnd),
      if (entry.checklistTotal > 0)
        '${entry.checklistDone} of ${entry.checklistTotal} done',
    ];
    return Dismissible(
      key: ValueKey('entry-${entry.id}'),
      background: _swipeBackground(context, delete: true), // swipe right
      secondaryBackground: _swipeBackground(
        context,
        delete: false,
      ), // swipe left
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          await _togglePin(context, ref);
          return false; // pinning keeps the plan on screen
        }
        // The delete takes the plan off the list itself (and puts it back if
        // it fails), so the swipe never leaves a dismissed widget behind.
        await _delete(context, ref);
        return false;
      },
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: _pinLabel):
              () => _togglePin(context, ref),
          const CustomSemanticsAction(label: 'Delete'):
              () => _delete(context, ref),
        },
        child: GestureDetector(
          onLongPress: () => _menu(context, ref),
          child: InfoRowWidget(
            // No leading icon: like Notes, the title and date carry the row.
            leadingWidget: const SizedBox.shrink(),
            avatarRadius: 0,
            iconSize: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.xs,
            ),
            title: entry.title,
            subtitle: MyDateFormat.join(parts),
            titleMaxLines: 1,
            subTitleMaxLines: 1,
            showDivider: !last,
            // Only the "new from your partner" dot, never an arrow.
            disableTrailing: !entry.hasNew,
            trailing: entry.hasNew ? const PlanningNewDot() : null,
            onTap: () {
              if (entry.hasNew) {
                ref.read(planningEntriesProvider(args).notifier).markSeen(entry.id);
              }
              onTap();
            },
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

  /// Set once Save is tapped with no title, so the field says so.
  bool _tried = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// Save creates the plan; with no title the sheet stays open and says so.
  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _tried = true);
      return;
    }
    popPlanningSheet(context, (title: title, useTemplate: _useTemplate));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      BottomSheetHeader(title: 'New plan', actionLabel: 'Save', onPressed: _save),
      AppTextFormField(
        controller: _title,
        autofocus: true,
        label: 'Title',
        hintText: 'Lisbon in May',
        labelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        errorText: _tried && _title.text.trim().isEmpty ? 'Give it a title' : null,
        textInputAction: TextInputAction.done,
        inputFormatters: [CodePointLengthFormatter(120)],
        buildCounter: codePointCounter(_title, 120),
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        onFieldSubmitted: (_) => _save(),
      ),
      const Gap(Spacing.sm),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: true,
            label: Text('Use template'),
            icon: Icon(Icons.auto_awesome_rounded),
          ),
          ButtonSegment(
            value: false,
            label: Text('Start blank'),
            icon: Icon(Icons.note_add_outlined),
          ),
        ],
        selected: {_useTemplate},
        onSelectionChanged: (s) => setState(() => _useTemplate = s.first),
      ),
    ],
  );
}
