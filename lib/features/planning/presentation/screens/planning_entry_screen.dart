import 'package:attune/app/theme/design_tokens.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
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
import '../widgets/budget_block_view.dart';
import '../widgets/checklist_block_view.dart';
import '../widgets/countdown_block_view.dart';
import '../widgets/date_poll_block_view.dart';
import '../widgets/dual_clock_block_view.dart';
import '../widgets/progress_block_view.dart';
import '../widgets/date_block_view.dart';
import '../widgets/expenses_block_view.dart';
import '../../domain/expense_view.dart';
import '../widgets/link_block_view.dart';
import '../widgets/photo_block_view.dart';
import '../widgets/place_block_view.dart';
import '../widgets/table_block_view.dart';
import '../widgets/inline_text_block.dart';
import '../widgets/planning_block_motion.dart';
import '../widgets/planning_doc_scope.dart';
import '../widgets/planning_ribbon.dart';
import '../../domain/delta_sanitizer.dart';

enum _EntryMenu { done, reopen, next, splitOn, splitOff }

enum _BlockMenu { edit, up, down, delete }

/// One plan, laid out as a document: its title, then its blocks, with a
/// Home | Insert ribbon above the keyboard. Text is edited in place.
/// With [openEditor] (a new note) the cursor starts in the first text block.
class PlanningEntryScreen extends ConsumerStatefulWidget {
  const PlanningEntryScreen({
    super.key,
    required this.relationshipId,
    required this.entryId,
    this.openEditor = false,
    this.categoryId,
    this.categoryName,
  });
  final String relationshipId;
  final String entryId;
  final bool openEditor;

  /// When opened from its category's list: the app-bar title is shown at
  /// once and flies in from the list. Otherwise it appears once loaded.
  final String? categoryId;
  final String? categoryName;

  @override
  ConsumerState<PlanningEntryScreen> createState() => _PlanningEntryScreenState();
}

class _PlanningEntryScreenState extends ConsumerState<PlanningEntryScreen> {
  final _doc = PlanningDocController();

  @override
  void dispose() {
    _doc.dispose();
    super.dispose();
  }

  /// A new note closed without writing anything is removed, so backing out
  /// never leaves empty "New note" plans behind (review m1). Anything
  /// typed (saved or not), renamed or added keeps the note.
  void _discardIfUntouched() {
    final args = (relationshipId: widget.relationshipId, entryId: widget.entryId);
    final detail = ref.read(planningEntryProvider(args)).valueOrNull;
    if (detail == null || _doc.anyText) return;
    final untouched =
        detail.entry.categorySeedKey == 'notes' &&
        detail.entry.title == planningNewNoteTitle &&
        detail.blocks.every((b) => b.type == PlanningBlockType.text && (b.plainText ?? '').trim().isEmpty);
    if (!untouched) return;
    final repo = ref.read(planningRepositoryProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final list = (relationshipId: widget.relationshipId, categoryId: detail.entry.categoryId, group: 'open');
    repo
        .deleteEntry(widget.entryId)
        .then(
          (_) => container.invalidate(planningEntriesProvider(list)),
          onError: (Object _) {},
        ); // keep the empty note rather than show an error for a non-action
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop && widget.openEditor) _discardIfUntouched();
    },
    child: PlanningDocScope(
      controller: _doc,
      child: _EntryBody(
        relationshipId: widget.relationshipId,
        entryId: widget.entryId,
        doc: _doc,
        focusFirstText: widget.openEditor,
        categoryId: widget.categoryId,
        categoryName: widget.categoryName,
      ),
    ),
  );
}

class _EntryBody extends ConsumerWidget {
  const _EntryBody({
    required this.relationshipId,
    required this.entryId,
    required this.doc,
    required this.focusFirstText,
    this.categoryId,
    this.categoryName,
  });
  final String relationshipId;
  final String entryId;
  final PlanningDocController doc;
  final bool focusFirstText;
  final String? categoryId;
  final String? categoryName;

  PlanningEntryArgs get _args => (relationshipId: relationshipId, entryId: entryId);

  Future<void> _guard(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, PlanningEntryDetail d, _EntryMenu m) async {
    final ctl = ref.read(planningEntryProvider(_args).notifier);
    switch (m) {
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
          final copy = await ref
              .read(planningRepositoryProvider)
              .duplicateEntry(sourceId: entryId, newId: const Uuid().v4(), title: d.entry.title);
          if (context.mounted) {
            await Navigator.of(context).pushReplacement(
              planningRoute(PlanningEntryScreen(relationshipId: relationshipId, entryId: copy.entry.id)),
            );
          }
        });
    }
  }

  /// A block's entrance and exit on the page (see [PlanningBlockMotion]).
  /// Listens to the document on its own, so only this block rebuilds.
  Widget _motion(PlanningBlock b, Widget child) {
    final enter = doc.appeared(b.id);
    return ListenableBuilder(
      listenable: doc,
      builder:
          (_, child) => PlanningBlockMotion(
            enter: enter,
            leaving: doc.isLeaving(b.id),
            onLeft: () => doc.left(b.id),
            child: child!,
          ),
      child: child,
    );
  }

  /// From the menu, the block collapses first; a swipe ([animate] false)
  /// has already animated it away. [context] must be the page's: the
  /// block's own is gone by the time the Undo snackbar shows.
  Future<void> _deleteBlock(
    BuildContext context,
    WidgetRef ref,
    PlanningEntryDetail d,
    PlanningBlock b, {
    bool animate = true,
  }) async {
    final index = d.blocks.indexOf(b);
    final ctl = ref.read(planningEntryProvider(_args).notifier);
    if (animate) {
      await doc.leave(b.id);
    } else {
      doc.unseen(b.id);
    }
    if (!context.mounted) return;
    await _guard(context, () => ctl.deleteBlock(b.id));
    if (!context.mounted) return;
    context.showInfoSnackbar(
      'Block removed',
      actionLabel: 'Undo',
      onAction: () => _guard(context, () => ctl.restoreBlock(b.id, index: index)),
    );
  }

  /// Insert, as in a word processor: the new block goes where the cursor
  /// is. Mid-paragraph, the paragraph splits around it; otherwise it goes
  /// after the text the cursor is in, after the block last tapped, or at
  /// the end. Link and Place ask for their content first.
  Future<void> _addBlock(BuildContext context, WidgetRef ref, PlanningBlockType type) async {
    final ctl = ref.read(planningEntryProvider(_args).notifier);
    Map<String, dynamic>? payload;
    if (type == PlanningBlockType.link) {
      final raw = await askPlanningText(
        context,
        title: 'Add a link',
        label: 'Web address',
        hint: 'airbnb.com/rooms/…',
        maxLength: 2048,
        keyboardType: TextInputType.url,
        validator: planningUrlError,
      );
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
    await _guard(context, () async {
      final blocks = ref.read(planningEntryProvider(_args)).valueOrNull?.blocks ?? const [];
      final active = doc.active;
      if (active != null && blocks.any((b) => b.id == active.blockId)) {
        if (!await active.flush()) return; // its text isn't saved; leave it as it is
        final c = active.controller;
        final plain = c.document.toPlainText();
        final at = c.selection.baseOffset.clamp(0, plain.length);
        final added =
            plain.substring(0, at).trim().isNotEmpty && plain.substring(at).trim().isNotEmpty
                ? await ctl.insertAtCursor(
                  type,
                  textBlockId: active.blockId,
                  version: active.version(),
                  before: sanitizeDelta(c.document.toDelta().slice(0, at).toJson()).ops,
                  after: sanitizeDelta(c.document.toDelta().slice(at).toJson()).ops,
                  payload: payload,
                )
                : await ctl.addBlock(type, payload: payload, afterId: active.blockId);
        if (type == PlanningBlockType.text) doc.focusWhenShown(added.id);
        return;
      }
      final selected = doc.selectedBlockId;
      final after = blocks.any((b) => b.id == selected) ? selected : null;
      final added = await ctl.addBlock(type, payload: payload, afterId: after);
      // Added at the end, possibly far below: scroll there so it is built
      // and its entrance is seen.
      if (after == null || after == blocks.last.id) doc.revealEnd();
      if (type == PlanningBlockType.text) doc.focusWhenShown(added.id);
    });
  }

  static Future<Map<String, dynamic>?> _askProgressKind(BuildContext context) =>
      showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder:
            (c) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
            ),
      );

  /// Blocks that put their options menu in their own heading row, so their
  /// body gets the full width instead of sharing it with a menu column.
  static const _menuInHeading = {
    PlanningBlockType.table,
    PlanningBlockType.checklist,
    PlanningBlockType.photo,
    PlanningBlockType.link, // beside its address, so its preview spans the note
  };

  /// Whether [b] places its own options menu, so its body takes the full width.
  static bool _menuInBlock(PlanningBlock b) => _menuInHeading.contains(b.type);

  Widget _blockBody(PlanningEntryDetail d, PlanningBlock b, {Widget? menu}) => switch (b.type) {
    PlanningBlockType.text => InlineTextBlock(
      args: _args,
      block: b,
      autofocus: focusFirstText && b.id == d.blocks.firstWhere((x) => x.type == PlanningBlockType.text).id,
    ),
    PlanningBlockType.checklist => ChecklistBlockView(args: _args, block: b, members: d.members, menu: menu),
    PlanningBlockType.date => DateBlockView(args: _args, block: b),
    PlanningBlockType.table => TableBlockView(args: _args, block: b, currency: d.entry.currency, menu: menu),
    PlanningBlockType.photo => PhotoBlockView(args: _args, block: b, menu: menu),
    PlanningBlockType.link => LinkBlockView(args: _args, block: b, menu: menu),
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
    // The page's context. Blocks' own contexts go away when a block is
    // deleted, so anything that runs after (the Undo snackbar) uses this.
    final page = context;
    final async = ref.watch(planningEntryProvider(_args));
    final entry = async.valueOrNull?.entry;
    final titleId = categoryId ?? entry?.categoryId;
    final titleName = categoryName ?? entry?.categoryName;
    // Tapping the page away from text, buttons and blocks hides the
    // keyboard (and so saves the text, which saves when it loses focus).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title:
              titleId == null || titleName == null ? null : PlanningCategoryTitle(categoryId: titleId, name: titleName),
          actions: [
            if (async.valueOrNull case final d?)
              PopupMenuButton<_EntryMenu>(
                tooltip: 'Plan options',
                icon: const Icon(Icons.more_vert), // vertical in app bars, on every platform
                onSelected: (m) => _menu(context, ref, d, m),
                itemBuilder:
                    (_) => [
                      if (!d.entry.isTemplate && d.entry.status == 'active')
                        const PopupMenuItem(value: _EntryMenu.done, child: Text('Mark done')),
                      if (!d.entry.isTemplate && d.entry.status != 'active')
                        const PopupMenuItem(value: _EntryMenu.reopen, child: Text('Reopen')),
                      if (!d.entry.isTemplate)
                        const PopupMenuItem(value: _EntryMenu.next, child: Text('Start next one')),
                      if (!d.entry.isTemplate && d.entry.split == null)
                        const PopupMenuItem(value: _EntryMenu.splitOn, child: Text('Split costs')),
                      if (!d.entry.isTemplate && d.entry.split != null)
                        const PopupMenuItem(value: _EntryMenu.splitOff, child: Text('Stop splitting costs')),
                    ],
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: async.when(
                skipLoadingOnReload: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (e, _) => PlanningErrorState(error: e, onRetry: () => ref.invalidate(planningEntryProvider(_args))),
                data: (d) {
                  doc.seed(d.blocks.map((b) => b.id)); // these appear without animating
                  return RefreshIndicator(
                    onRefresh: () => ref.refresh(planningEntryProvider(_args).future),
                    child: ReorderableListView.builder(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                      scrollController: doc.scroll,
                      buildDefaultDragHandles: false,
                      padding: Spacing.horizontalMd,
                      header: _Hero(detail: d, args: _args),
                      footer: const SizedBox(height: Spacing.xxl * 2),
                      itemCount: d.blocks.length,
                      onReorder:
                          (from, to) => _guard(
                            context,
                            () => ref
                                .read(planningEntryProvider(_args).notifier)
                                .moveBlock(d.blocks[from].id, to > from ? to - 1 : to),
                          ),
                      itemBuilder: (context, i) {
                        final b = d.blocks[i];
                        final name = b.title ?? planningBlockLabel(b.type);
                        final ctl = ref.read(planningEntryProvider(_args).notifier);
                        final expenseView = b.type == PlanningBlockType.expenses ? ref.watch(planningExpenseViewProvider(b.id)) : null;
                        final menu = PopupMenuButton<Object>(
                          tooltip: 'Options for $name',
                          onSelected:
                              (m) => switch (m) {
                                _BlockMenu.edit => editPlanningLink(page, ref, _args, b),
                                _BlockMenu.up => _guard(page, () => ctl.moveBlock(b.id, i - 1)),
                                _BlockMenu.down => _guard(page, () => ctl.moveBlock(b.id, i + 1)),
                                _BlockMenu.delete => _deleteBlock(page, ref, d, b),
                                // An Expenses block's view: only what this person sees.
                                PlanningExpenseSort sort =>
                                  ref.read(planningExpenseViewProvider(b.id).notifier).update((v) => v.withSort(sort)),
                                PlanningExpensePayer payer =>
                                  ref.read(planningExpenseViewProvider(b.id).notifier).update((v) => v.withPayer(payer.id)),
                                _ => null,
                              },
                          itemBuilder:
                              (_) => [
                                if (b.type == PlanningBlockType.link && b.linkUrl != null)
                                  const PopupMenuItem(value: _BlockMenu.edit, child: Text('Edit link')),
                                if (i > 0) const PopupMenuItem(value: _BlockMenu.up, child: Text('Move up')),
                                if (i < d.blocks.length - 1)
                                  const PopupMenuItem(value: _BlockMenu.down, child: Text('Move down')),
                                const PopupMenuItem(value: _BlockMenu.delete, child: Text('Delete')),
                                if (expenseView != null) ...[
                                  const PopupMenuDivider(),
                                  for (final (sort, label) in const [
                                    (PlanningExpenseSort.added, 'Order added'),
                                    (PlanningExpenseSort.lowest, 'Lowest to highest'),
                                    (PlanningExpenseSort.highest, 'Highest to lowest'),
                                  ])
                                    CheckedPopupMenuItem<Object>(
                                      value: sort,
                                      checked: expenseView.sort == sort,
                                      child: Text(label),
                                    ),
                                  const PopupMenuDivider(),
                                  CheckedPopupMenuItem<Object>(
                                    value: const PlanningExpensePayer(null),
                                    checked: expenseView.paidBy == null,
                                    child: const Text('Paid by anyone'),
                                  ),
                                  for (final m in d.members)
                                    CheckedPopupMenuItem<Object>(
                                      value: PlanningExpensePayer(m.id),
                                      checked: expenseView.paidBy == m.id,
                                      child: Text('Paid by ${planningMemberName(d.members, m.id)}'),
                                    ),
                                ],
                              ],
                        );
                        // Text is part of the page, not a card: no drag (long-press
                        // selects words) and no swipe (it would fight text selection).
                        // Its menu still moves and deletes it. A Date block with its
                        // date set reads the same way: a line in the note. So does a
                        // table: its grid is its own frame, and its rows own the swipe. Photos
                        // too: the stack is its own frame, and the swipe browses it. And a link:
                        // its preview reads as part of the note.
                        if (b.type == PlanningBlockType.text ||
                            b.type == PlanningBlockType.table ||
                            b.type == PlanningBlockType.photo ||
                            b.type == PlanningBlockType.link ||
                            (b.type == PlanningBlockType.date && b.dateStart != null)) {
                          final body = Padding(
                            padding: const EdgeInsets.only(bottom: Spacing.sm),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _menuInBlock(b)
                                  ? [Expanded(child: _blockBody(d, b, menu: menu))]
                                  : [Expanded(child: _blockBody(d, b)), menu],
                            ),
                          );
                          return KeyedSubtree(
                            key: ValueKey('block-${b.id}'),
                            child: _motion(
                              b,
                              b.type == PlanningBlockType.text
                                  ? body
                                  // Insert goes after the block last tapped.
                                  : Listener(onPointerDown: (_) => doc.select(b.id), child: body),
                            ),
                          );
                        }
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey('block-${b.id}'),
                          index: i,
                          child: _motion(
                            b,
                            Dismissible(
                              key: ValueKey('dismiss-${b.id}'),
                              direction: DismissDirection.startToEnd, // swipe right = delete, as everywhere in Planning
                              // The delete takes the row away itself (and puts it back if it fails),
                              // so the swipe never leaves a dismissed widget in the tree.
                              confirmDismiss: (_) async {
                                await _deleteBlock(page, ref, d, b, animate: false);
                                return false;
                              },
                              background: Container(
                                alignment: Alignment.centerLeft,
                                padding: Spacing.horizontalMd,
                                color: Theme.of(context).colorScheme.errorContainer,
                                child: const Icon(Icons.delete_outline_rounded),
                              ),
                              child: Listener(
                                // Insert goes after the block last tapped.
                                onPointerDown: (_) => doc.select(b.id),
                                child: CardInkWell(
                                  margin: const EdgeInsets.only(bottom: Spacing.smMd),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, 0, Spacing.sm),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: _menuInBlock(b)
                                          ? [Expanded(child: _blockBody(d, b, menu: menu))]
                                          : [Expanded(child: _blockBody(d, b)), menu],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            if (async.hasValue) PlanningRibbon(onInsert: (type) => _addBlock(context, ref, type)),
          ],
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
    final countdown =
        detail.blocks
            .where((b) => b.type == PlanningBlockType.countdown && b.countdownTarget != null)
            .firstOrNull
            ?.countdownTarget;
    final items = [
      for (final b in detail.blocks)
        if (b.type == PlanningBlockType.checklist) ...b.items,
    ];
    final done = items.where((i) => i.isChecked).length;
    final outbox = ref.watch(planningOutboxProvider);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.entry.isTemplate)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: Spacing.smMd),
              padding: Spacing.allSm,
              decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadiusTokens.smAll),
              child: Text('Template. New plans start from this.', style: TextStyle(color: scheme.onTertiaryContainer)),
            ),
          _TitleField(entry: detail.entry, args: args),
          const Gap(Spacing.sm),
          if (detail.entry.split case final split?) _SplitCard(detail: detail, split: split, args: args),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              if (date != null)
                Chip(
                  avatar: const Icon(Icons.event_rounded, size: 18),
                  label: Text(formatPlanningRange(date.dateStart, date.dateEnd)),
                ),
              if (countdown != null && !countdown.isBefore(DateUtils.dateOnly(DateTime.now())))
                Chip(
                  avatar: const Icon(Icons.hourglass_bottom_rounded, size: 18),
                  label: Text(planningCountdownLabel(countdown, DateTime.now())),
                ),
              if (items.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.checklist_rounded, size: 18),
                  label: Text('$done of ${items.length} done'),
                ),
              ValueListenableBuilder<int>(
                valueListenable: outbox.pendingCount,
                builder:
                    (_, n, __) =>
                        n == 0
                            ? const SizedBox.shrink()
                            : Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: Spacing.xs,
                              children: [
                                Chip(
                                  avatar: const Icon(Icons.cloud_upload_outlined, size: 18),
                                  label: Text(n == 1 ? '1 change waiting to sync' : '$n changes waiting to sync'),
                                ),
                                TextButton(
                                  onPressed:
                                      () => outbox.replay().then((r) {
                                        if (r.sent > 0 || r.dropped.isNotEmpty) {
                                          ref.invalidate(planningEntryProvider(args));
                                        }
                                      }),
                                  child: const Text('Retry sync'),
                                ),
                              ],
                            ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: outbox.droppedCount,
                builder:
                    (_, n, __) =>
                        n == 0
                            ? const SizedBox.shrink()
                            : Chip(
                              avatar: Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
                              label: Text(n == 1 ? "1 change couldn't be saved" : "$n changes couldn't be saved"),
                              deleteButtonTooltipMessage: 'Dismiss',
                              onDeleted: outbox.acknowledgeDropped,
                            ),
              ),
            ],
          ),
        ],
      ),
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
    final ok = await planningConfirm(
      context,
      title: 'Settle up?',
      message: 'Marks everything so far as paid back. New expenses start a fresh balance.',
      confirmText: 'Settle',
    );
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
      child: Row(
        children: [
          Icon(Icons.balance_rounded, color: scheme.onSecondaryContainer),
          const Gap(Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (split.isEven)
                  Text('All even', style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSecondaryContainer))
                else
                  for (final b in split.balances)
                    Text(
                      '${planningMemberName(detail.members, b.owedBy)} owes '
                      '${planningMemberName(detail.members, b.owedTo)} ${formatPlanningMoney(b.minor, b.currency)}',
                      style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSecondaryContainer),
                    ),
              ],
            ),
          ),
          if (!split.isEven) TextButton(onPressed: () => _settle(context, ref), child: const Text('Mark settled')),
        ],
      ),
    );
  }
}

/// The plan's title, edited in place like a document title. Saves when
/// the cursor leaves it or on Done; a blank title is put back.
class _TitleField extends ConsumerStatefulWidget {
  const _TitleField({required this.entry, required this.args});
  final PlanningEntry entry;
  final PlanningEntryArgs args;

  @override
  ConsumerState<_TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends ConsumerState<_TitleField> {
  late final _c = TextEditingController(text: widget.entry.title);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_TitleField old) {
    super.didUpdateWidget(old);
    // A partner's rename, or a new note titled from its first line.
    if (!_focus.hasFocus && widget.entry.title != _c.text) _c.text = widget.entry.title;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _c.text.trim();
    if (t.isEmpty) {
      _c.text = widget.entry.title;
      return;
    }
    if (t == widget.entry.title) return;
    try {
      await ref.read(planningEntryProvider(widget.args).notifier).rename(t);
    } catch (e) {
      if (mounted) {
        _c.text = widget.entry.title;
        showPlanningError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48), // tap target (spec §5)
    child: TextField(
      controller: _c,
      focusNode: _focus,
      style: Theme.of(context).textTheme.headlineSmall,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      inputFormatters: [CodePointLengthFormatter(120)],
      maxLines: null,
      decoration: const InputDecoration(
        hintText: 'Title',
        // Plain document title: no fill and no outline in any state (the
        // app's input theme adds both to text fields).
        filled: false,
        fillColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      onSubmitted: (_) => _focus.unfocus(),
    ),
  );
}
