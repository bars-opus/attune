import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_fab.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';
import '../widgets/block_tool_tray.dart';
import '../widgets/checklist_block_view.dart';
import '../widgets/date_block_view.dart';
import '../widgets/text_block_view.dart';

enum _EntryMenu { rename, done, reopen, next }

enum _BlockMenu { up, down, delete }

class PlanningV2EntryScreen extends ConsumerWidget {
  const PlanningV2EntryScreen({super.key, required this.relationshipId, required this.entryId});
  final String relationshipId;
  final String entryId;

  PlanningEntryArgs get _args => (relationshipId: relationshipId, entryId: entryId);

  Future<void> _guard(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) showPlanningV2Error(context, e);
    }
  }

  Future<String?> _askTitle(BuildContext context, String current) {
    final c = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: c, autofocus: true, maxLength: 120),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
        ],
      ),
    ).whenComplete(c.dispose);
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, PlanningEntryDetail d, _EntryMenu m) async {
    final ctl = ref.read(planningV2EntryProvider(_args).notifier);
    switch (m) {
      case _EntryMenu.rename:
        final t = await _askTitle(context, d.entry.title);
        if (t != null && t.isNotEmpty && context.mounted) await _guard(context, () => ctl.rename(t));
      case _EntryMenu.done:
        await _guard(context, () => ctl.setStatus('done'));
      case _EntryMenu.reopen:
        await _guard(context, () => ctl.setStatus('active'));
      case _EntryMenu.next:
        await _guard(context, () async {
          final copy = await ref.read(planningV2RepositoryProvider)
              .duplicateEntry(sourceId: entryId, newId: const Uuid().v4(), title: d.entry.title);
          if (context.mounted) {
            await Navigator.of(context).pushReplacement(planningV2Route(
                PlanningV2EntryScreen(relationshipId: relationshipId, entryId: copy.entry.id)));
          }
        });
    }
  }

  Future<void> _deleteBlock(BuildContext context, WidgetRef ref, PlanningEntryDetail d, PlanningBlock b) async {
    final index = d.blocks.indexOf(b);
    final ctl = ref.read(planningV2EntryProvider(_args).notifier);
    await _guard(context, () => ctl.deleteBlock(b.id));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Block removed'),
      action: SnackBarAction(label: 'Undo', onPressed: () => _guard(context, () => ctl.restoreBlock(b.id, index: index))),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(planningV2EntryProvider(_args));
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
              ],
            ),
        ],
      ),
      floatingActionButton: async.hasValue
          ? AppFab(
              heroTag: 'planning-v2-add-block',
              icon: Icons.add_rounded,
              label: 'Add block',
              onPressed: () async {
                final type = await showBlockToolTray(context);
                if (type != null && context.mounted) {
                  await _guard(context, () => ref.read(planningV2EntryProvider(_args).notifier).addBlock(type));
                }
              },
            )
          : null,
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PlanningV2ErrorState(error: e, onRetry: () => ref.invalidate(planningV2EntryProvider(_args))),
        data: (d) => RefreshIndicator(
          onRefresh: () => ref.refresh(planningV2EntryProvider(_args).future),
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: Spacing.horizontalMd,
            header: _Hero(detail: d, args: _args),
            footer: const SizedBox(height: Spacing.xxl * 2),
            itemCount: d.blocks.length,
            onReorder: (from, to) => _guard(context,
                () => ref.read(planningV2EntryProvider(_args).notifier).moveBlock(d.blocks[from].id, to > from ? to - 1 : to)),
            itemBuilder: (context, i) {
              final b = d.blocks[i];
              final name = b.title ?? switch (b.type) {
                PlanningBlockType.text => 'Text',
                PlanningBlockType.checklist => 'Checklist',
                PlanningBlockType.date => 'Date',
                PlanningBlockType.unsupported => 'Block',
              };
              final ctl = ref.read(planningV2EntryProvider(_args).notifier);
              return ReorderableDelayedDragStartListener(
                key: ValueKey('block-${b.id}'),
                index: i,
                child: Dismissible(
                  key: ValueKey('dismiss-${b.id}'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _deleteBlock(context, ref, d, b),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: Spacing.horizontalMd,
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  child: CardInkWell(
                    margin: const EdgeInsets.only(bottom: Spacing.smMd),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, 0, Spacing.sm),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: switch (b.type) {
                            PlanningBlockType.text => TextBlockView(args: _args, block: b),
                            PlanningBlockType.checklist => ChecklistBlockView(args: _args, block: b, members: d.members),
                            PlanningBlockType.date => DateBlockView(args: _args, block: b),
                            PlanningBlockType.unsupported => const Padding(
                                padding: EdgeInsets.symmetric(vertical: Spacing.sm),
                                child: Text('This block needs a newer version of Attune.'),
                              ),
                          },
                        ),
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
    final items = [for (final b in detail.blocks) if (b.type == PlanningBlockType.checklist) ...b.items];
    final done = items.where((i) => i.isChecked).length;
    final outbox = ref.watch(planningV2OutboxProvider);
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
        Wrap(spacing: Spacing.sm, runSpacing: Spacing.xs, children: [
          if (date != null)
            Chip(avatar: const Icon(Icons.event_rounded, size: 18), label: Text(formatPlanningRange(date.dateStart, date.dateEnd))),
          if (items.isNotEmpty)
            Chip(avatar: const Icon(Icons.checklist_rounded, size: 18), label: Text('$done of ${items.length} done')),
          ValueListenableBuilder<int>(
            valueListenable: outbox.pendingCount,
            builder: (_, n, __) => n == 0
                ? const SizedBox.shrink()
                : Chip(
                    avatar: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(n == 1 ? '1 change waiting to sync' : '$n changes waiting to sync'),
                  ),
          ),
        ]),
      ]),
    );
  }
}
