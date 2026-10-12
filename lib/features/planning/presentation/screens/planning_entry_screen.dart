import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_fab.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/planning_models.dart';
import '../../domain/code_point_limit.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';
import '../../data/planning_error.dart';
import '../../domain/planning_money.dart';
import '../widgets/block_tool_tray.dart';
import 'planning_text_editor_screen.dart';
import '../widgets/budget_block_view.dart';
import '../widgets/checklist_block_view.dart';
import '../widgets/countdown_block_view.dart';
import '../widgets/date_poll_block_view.dart';
import '../widgets/dual_clock_block_view.dart';
import '../widgets/progress_block_view.dart';
import '../widgets/date_block_view.dart';
import '../widgets/expenses_block_view.dart';
import '../widgets/link_block_view.dart';
import '../widgets/photo_block_view.dart';
import '../widgets/place_block_view.dart';
import '../widgets/table_block_view.dart';
import '../widgets/text_block_view.dart';

enum _EntryMenu { rename, done, reopen, next, splitOn, splitOff }

enum _BlockMenu { up, down, delete }

/// One plan. With [openEditor] (a new note), the first text block opens in
/// the editor as soon as the plan has loaded, so writing starts at once.
class PlanningEntryScreen extends ConsumerStatefulWidget {
  const PlanningEntryScreen({
    super.key,
    required this.relationshipId,
    required this.entryId,
    this.openEditor = false,
  });
  final String relationshipId;
  final String entryId;
  final bool openEditor;

  @override
  ConsumerState<PlanningEntryScreen> createState() => _PlanningEntryScreenState();
}

class _PlanningEntryScreenState extends ConsumerState<PlanningEntryScreen> {
  bool _editorOpened = false;

  @override
  void initState() {
    super.initState();
    if (!widget.openEditor) return;
    ref.listenManual<AsyncValue<PlanningEntryDetail>>(
      planningEntryProvider((relationshipId: widget.relationshipId, entryId: widget.entryId)),
      (_, next) {
        final detail = next.valueOrNull;
        if (_editorOpened || detail == null) return;
        final text = detail.blocks.where((b) => b.type == PlanningBlockType.text).firstOrNull;
        if (text == null) return;
        _editorOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final saved = await Navigator.of(context).push<bool>(planningRoute(PlanningTextEditorScreen(
              args: (relationshipId: widget.relationshipId, entryId: widget.entryId), block: text)));
          if (saved != true && mounted) await _discardIfUntouched();
        });
      },
      fireImmediately: true,
    );
  }

  /// A new note closed without writing anything is removed, so backing out
  /// never leaves empty "New note" plans behind (review m1). Anything
  /// typed, renamed or added keeps the note.
  Future<void> _discardIfUntouched() async {
    final args = (relationshipId: widget.relationshipId, entryId: widget.entryId);
    final detail = ref.read(planningEntryProvider(args)).valueOrNull;
    if (detail == null) return;
    final untouched = detail.entry.categorySeedKey == 'notes' &&
        detail.entry.title == planningNewNoteTitle &&
        detail.blocks.every((b) => b.type == PlanningBlockType.text && (b.plainText ?? '').trim().isEmpty);
    if (!untouched) return;
    try {
      await ref.read(planningRepositoryProvider).deleteEntry(widget.entryId);
    } catch (_) {
      return; // keep the empty note rather than show an error for a non-action
    }
    ref.invalidate(planningEntriesProvider(
        (relationshipId: widget.relationshipId, categoryId: detail.entry.categoryId, group: 'open')));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) =>
      _EntryBody(relationshipId: widget.relationshipId, entryId: widget.entryId);
}

class _EntryBody extends ConsumerWidget {
  const _EntryBody({required this.relationshipId, required this.entryId});
  final String relationshipId;
  final String entryId;

  PlanningEntryArgs get _args => (relationshipId: relationshipId, entryId: entryId);

  Future<void> _guard(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<String?> _askTitle(BuildContext context, String current) {
    final c = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: c,
          autofocus: true,
          inputFormatters: [CodePointLengthFormatter(120)],
          buildCounter: codePointCounter(c, 120),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
        ],
      ),
    ).whenComplete(c.dispose);
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, PlanningEntryDetail d, _EntryMenu m) async {
    final ctl = ref.read(planningEntryProvider(_args).notifier);
    switch (m) {
      case _EntryMenu.rename:
        final t = await _askTitle(context, d.entry.title);
        if (t != null && t.isNotEmpty && context.mounted) await _guard(context, () => ctl.rename(t));
      case _EntryMenu.done:
        await _guard(context, () => ctl.setStatus('done'));
      case _EntryMenu.reopen:
        await _guard(context, () => ctl.setStatus('active'));
      case _EntryMenu.splitOn:
        await _guard(context, () => ctl.setSplit(true));
      case _EntryMenu.splitOff:
        await _guard(context, () => ctl.setSplit(false));
      case _EntryMenu.next:
        await _guard(context, () async {
          final copy = await ref.read(planningRepositoryProvider)
              .duplicateEntry(sourceId: entryId, newId: const Uuid().v4(), title: d.entry.title);
          if (context.mounted) {
            await Navigator.of(context).pushReplacement(planningRoute(
                PlanningEntryScreen(relationshipId: relationshipId, entryId: copy.entry.id)));
          }
        });
    }
  }

  Future<void> _deleteBlock(BuildContext context, WidgetRef ref, PlanningEntryDetail d, PlanningBlock b) async {
    final index = d.blocks.indexOf(b);
    final ctl = ref.read(planningEntryProvider(_args).notifier);
    await _guard(context, () => ctl.deleteBlock(b.id));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Block removed'),
      action: SnackBarAction(label: 'Undo', onPressed: () => _guard(context, () => ctl.restoreBlock(b.id, index: index))),
    ));
  }

  /// Link and Place ask for their content first; the rest start empty.
  Future<void> _addBlock(BuildContext context, WidgetRef ref, PlanningBlockType type) async {
    final ctl = ref.read(planningEntryProvider(_args).notifier);
    Map<String, dynamic>? payload;
    if (type == PlanningBlockType.link) {
      final raw = await askPlanningText(context,
          title: 'Add a link', label: 'Web address', hint: 'airbnb.com/rooms/…', action: 'Add', maxLength: 2048,
          keyboardType: TextInputType.url);
      if (raw == null || !context.mounted) return;
      final url = normalizePlanningUrl(raw);
      if (url == null) return showPlanningError(context, const PlanningInvalidInput('url'));
      payload = {'url': url};
    } else if (type == PlanningBlockType.place) {
      final place = await showPlanningPlacePicker(context);
      if (place == null || !context.mounted) return;
      payload = place.toJson();
    } else if (type == PlanningBlockType.progress) {
      payload = await _askProgressKind(context);
      if (payload == null || !context.mounted) return;
    }
    await _guard(context, () => ctl.addBlock(type, payload: payload));
  }

  static Future<Map<String, dynamic>?> _askProgressKind(BuildContext context) =>
      showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: const Text('Saving money'),
              subtitle: const Text('Add amounts toward a target'),
              onTap: () => Navigator.pop(c, {'mode': 'numeric', 'unit': 'money'}),
            ),
            ListTile(
              leading: const Icon(Icons.exposure_plus_1_rounded),
              title: const Text('Counting something'),
              subtitle: const Text('Workouts, books, nights cooked at home'),
              onTap: () => Navigator.pop(c, {'mode': 'numeric', 'unit': 'count'}),
            ),
            ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('Following a checklist'),
              subtitle: const Text("Fills up as this plan's checklist is ticked"),
              onTap: () => Navigator.pop(c, {'mode': 'checklist'}),
            ),
          ]),
        ),
      );

  Widget _blockBody(PlanningEntryDetail d, PlanningBlock b) => switch (b.type) {
        PlanningBlockType.text => TextBlockView(args: _args, block: b),
        PlanningBlockType.checklist => ChecklistBlockView(args: _args, block: b, members: d.members),
        PlanningBlockType.date => DateBlockView(args: _args, block: b),
        PlanningBlockType.table => TableBlockView(args: _args, block: b, currency: d.entry.currency),
        PlanningBlockType.photo => PhotoBlockView(args: _args, block: b),
        PlanningBlockType.link => LinkBlockView(args: _args, block: b),
        PlanningBlockType.place => PlaceBlockView(args: _args, block: b),
        PlanningBlockType.expenses => ExpensesBlockView(args: _args, block: b, detail: d),
        PlanningBlockType.budget => BudgetBlockView(args: _args, block: b, defaultCurrency: d.entry.currency),
        PlanningBlockType.datePoll => DatePollBlockView(args: _args, block: b, members: d.members),
        PlanningBlockType.countdown => CountdownBlockView(args: _args, block: b, detail: d),
        PlanningBlockType.progress => ProgressBlockView(args: _args, block: b, defaultCurrency: d.entry.currency),
        PlanningBlockType.dualClock => DualClockBlockView(args: _args, block: b),
        PlanningBlockType.unsupported => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Text('This block needs a newer version of Attune.'),
          ),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(planningEntryProvider(_args));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.valueOrNull?.entry.categoryName ?? ''),
        actions: [
          if (async.valueOrNull case final d?)
            PopupMenuButton<_EntryMenu>(
              tooltip: 'Plan options',
              onSelected: (m) => _menu(context, ref, d, m),
              itemBuilder: (_) => [
                const PopupMenuItem(value: _EntryMenu.rename, child: Text('Rename')),
                if (!d.entry.isTemplate && d.entry.status == 'active')
                  const PopupMenuItem(value: _EntryMenu.done, child: Text('Mark done')),
                if (!d.entry.isTemplate && d.entry.status != 'active')
                  const PopupMenuItem(value: _EntryMenu.reopen, child: Text('Reopen')),
                if (!d.entry.isTemplate) const PopupMenuItem(value: _EntryMenu.next, child: Text('Start next one')),
                if (!d.entry.isTemplate && d.entry.split == null)
                  const PopupMenuItem(value: _EntryMenu.splitOn, child: Text('Split costs')),
                if (!d.entry.isTemplate && d.entry.split != null)
                  const PopupMenuItem(value: _EntryMenu.splitOff, child: Text('Stop splitting costs')),
              ],
            ),
        ],
      ),
      floatingActionButton: async.hasValue
          ? AppFab(
              heroTag: 'planning-add-block',
              icon: Icons.add_rounded,
              label: 'Add block',
              onPressed: () async {
                final type = await showBlockToolTray(context);
                if (type != null && context.mounted) await _addBlock(context, ref, type);
              },
            )
          : null,
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PlanningErrorState(error: e, onRetry: () => ref.invalidate(planningEntryProvider(_args))),
        data: (d) => RefreshIndicator(
          onRefresh: () => ref.refresh(planningEntryProvider(_args).future),
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: Spacing.horizontalMd,
            header: _Hero(detail: d, args: _args),
            footer: const SizedBox(height: Spacing.xxl * 2),
            itemCount: d.blocks.length,
            onReorder: (from, to) => _guard(context,
                () => ref.read(planningEntryProvider(_args).notifier).moveBlock(d.blocks[from].id, to > from ? to - 1 : to)),
            itemBuilder: (context, i) {
              final b = d.blocks[i];
              final name = b.title ?? planningBlockLabel(b.type);
              final ctl = ref.read(planningEntryProvider(_args).notifier);
              return ReorderableDelayedDragStartListener(
                key: ValueKey('block-${b.id}'),
                index: i,
                child: Dismissible(
                  key: ValueKey('dismiss-${b.id}'),
                  direction: DismissDirection.startToEnd, // swipe right = delete, as everywhere in Planning
                  // The delete takes the row away itself (and puts it back if it fails),
                  // so the swipe never leaves a dismissed widget in the tree.
                  confirmDismiss: (_) async {
                    await _deleteBlock(context, ref, d, b);
                    return false;
                  },
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: Spacing.horizontalMd,
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  child: CardInkWell(
                    margin: const EdgeInsets.only(bottom: Spacing.smMd),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, 0, Spacing.sm),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: _blockBody(d, b)),
                        PopupMenuButton<_BlockMenu>(
                          tooltip: 'Options for $name',
                          onSelected: (m) => switch (m) {
                            _BlockMenu.up => _guard(context, () => ctl.moveBlock(b.id, i - 1)),
                            _BlockMenu.down => _guard(context, () => ctl.moveBlock(b.id, i + 1)),
                            _BlockMenu.delete => _deleteBlock(context, ref, d, b),
                          },
                          itemBuilder: (_) => [
                            if (i > 0) const PopupMenuItem(value: _BlockMenu.up, child: Text('Move up')),
                            if (i < d.blocks.length - 1) const PopupMenuItem(value: _BlockMenu.down, child: Text('Move down')),
                            const PopupMenuItem(value: _BlockMenu.delete, child: Text('Delete')),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.detail, required this.args});
  final PlanningEntryDetail detail;
  final PlanningEntryArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = detail.blocks.where((b) => b.type == PlanningBlockType.date && b.dateStart != null).firstOrNull;
    final countdown = detail.blocks
        .where((b) => b.type == PlanningBlockType.countdown && b.countdownTarget != null)
        .firstOrNull
        ?.countdownTarget;
    final items = [for (final b in detail.blocks) if (b.type == PlanningBlockType.checklist) ...b.items];
    final done = items.where((i) => i.isChecked).length;
    final outbox = ref.watch(planningOutboxProvider);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (detail.entry.isTemplate)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: Spacing.smMd),
            padding: Spacing.allSm,
            decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadiusTokens.smAll),
            child: Text('Template. New plans start from this.', style: TextStyle(color: scheme.onTertiaryContainer)),
          ),
        Text(detail.entry.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: Spacing.sm),
        if (detail.entry.split case final split?) _SplitCard(detail: detail, split: split, args: args),
        Wrap(spacing: Spacing.sm, runSpacing: Spacing.xs, children: [
          if (date != null)
            Chip(avatar: const Icon(Icons.event_rounded, size: 18), label: Text(formatPlanningRange(date.dateStart, date.dateEnd))),
          if (countdown != null && !countdown.isBefore(DateUtils.dateOnly(DateTime.now())))
            Chip(
                avatar: const Icon(Icons.hourglass_bottom_rounded, size: 18),
                label: Text(planningCountdownLabel(countdown, DateTime.now()))),
          if (items.isNotEmpty)
            Chip(avatar: const Icon(Icons.checklist_rounded, size: 18), label: Text('$done of ${items.length} done')),
          ValueListenableBuilder<int>(
            valueListenable: outbox.pendingCount,
            builder: (_, n, __) => n == 0
                ? const SizedBox.shrink()
                : Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: Spacing.xs, children: [
                    Chip(
                      avatar: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text(n == 1 ? '1 change waiting to sync' : '$n changes waiting to sync'),
                    ),
                    TextButton(
                      onPressed: () => outbox.replay().then((r) {
                        if (r.sent > 0 || r.dropped.isNotEmpty) ref.invalidate(planningEntryProvider(args));
                      }),
                      child: const Text('Retry sync'),
                    ),
                  ]),
          ),
          ValueListenableBuilder<int>(
            valueListenable: outbox.droppedCount,
            builder: (_, n, __) => n == 0
                ? const SizedBox.shrink()
                : Chip(
                    avatar: Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
                    label: Text(n == 1 ? "1 change couldn't be saved" : "$n changes couldn't be saved"),
                    deleteButtonTooltipMessage: 'Dismiss',
                    onDeleted: outbox.acknowledgeDropped,
                  ),
          ),
        ]),
      ]),
    );
  }
}

/// Who evens out with whom, per currency, inside this plan only (spec D6).
class _SplitCard extends ConsumerWidget {
  const _SplitCard({required this.detail, required this.split, required this.args});
  final PlanningEntryDetail detail;
  final PlanningSplit split;
  final PlanningEntryArgs args;

  Future<void> _settle(BuildContext context, WidgetRef ref) async {
    final ok = await planningConfirm(context,
        title: 'Settle up?',
        message: 'Marks everything so far as paid back. New expenses start a fresh balance.',
        confirmText: 'Settle');
    if (!ok || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).settleSplit();
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Spacing.smMd),
      padding: Spacing.allSm,
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadiusTokens.smAll),
      child: Row(children: [
        Icon(Icons.balance_rounded, color: scheme.onSecondaryContainer),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (split.isEven)
              Text('All even', style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSecondaryContainer))
            else
              for (final b in split.balances)
                Text(
                  '${planningMemberName(detail.members, b.owedBy)} owes '
                  '${planningMemberName(detail.members, b.owedTo)} ${formatPlanningMoney(b.minor, b.currency)}',
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSecondaryContainer),
                ),
          ]),
        ),
        if (!split.isEven) TextButton(onPressed: () => _settle(context, ref), child: const Text('Mark settled')),
      ]),
    );
  }
}
