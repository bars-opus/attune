import 'package:attune/app/theme/design_tokens.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_models.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

/// Date options each partner marks "works for me". An option both chose
/// can be locked in, which turns the poll into a Date block.
class DatePollBlockView extends ConsumerWidget {
  const DatePollBlockView({super.key, required this.args, required this.block, required this.members});
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final List<PlanningMember> members;

  Future<void> _guard(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<void> _suggest(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
        context: context, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 5), helpText: 'Suggest dates');
    if (r == null || !context.mounted) return;
    await _guard(context, () => ref.read(planningEntryProvider(args).notifier).addPollOption(block.id, r.start, r.end));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, PlanningItem option) async {
    final ctl = ref.read(planningEntryProvider(args).notifier);
    final index = block.items.indexOf(option);
    try {
      await ctl.deleteItem(block.id, option.id);
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
      return; // nothing was removed, so there is nothing to undo
    }
    if (!context.mounted) return;
    context.showInfoSnackbar('Dates removed',
        actionLabel: 'Undo', onAction: () => ctl.restoreItem(block.id, option.id, index: index));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final me = ref.watch(planningCurrentUserIdProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(block.title ?? 'Date poll', style: theme.textTheme.titleMedium),
      const Gap(Spacing.xs),
      if (block.items.isEmpty)
        Text('Suggest a few dates and vote on what works.', style: TextStyle(color: scheme.outline)),
      for (final option in block.items)
        Dismissible(
          key: ValueKey('option-${option.id}'),
          direction: DismissDirection.startToEnd, // swipe right = delete, as everywhere in Planning
          background: Container(
            alignment: Alignment.centerLeft,
            padding: Spacing.horizontalMd,
            color: scheme.errorContainer,
            child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
          ),
          // The delete takes the row away itself (and puts it back if it fails),
          // so the swipe never leaves a dismissed widget in the tree.
          confirmDismiss: (_) async {
            await _delete(context, ref, option);
            return false;
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(formatPlanningRange(option.dateStart, option.dateEnd), style: theme.textTheme.bodyLarge),
                ),
                // Initials, not colour alone, say who it works for.
                for (final m in members)
                  if (option.votes.contains(m.id))
                    Padding(
                      padding: const EdgeInsets.only(left: Spacing.xs),
                      child: Semantics(
                        label: 'Works for ${m.displayName}',
                        excludeSemantics: true,
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor: scheme.primaryContainer,
                          child: Text(m.initial, style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer)),
                        ),
                      ),
                    ),
              ]),
              const Gap(Spacing.xs),
              Wrap(spacing: Spacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                FilterChip(
                  label: const Text('Works for me'),
                  selected: option.votes.contains(me),
                  onSelected: (v) => _guard(
                      context, () => ref.read(planningEntryProvider(args).notifier).vote(block.id, option, v)),
                ),
                if (members.isNotEmpty && members.every((m) => option.votes.contains(m.id)))
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: const Text('Lock it in'),
                    onPressed: () => _guard(
                        context, () => ref.read(planningEntryProvider(args).notifier).lockPoll(block.id, option.id)),
                  ),
              ]),
            ]),
          ),
        ),
      if (block.items.length < 20)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.date_range_rounded),
            label: const Text('Suggest dates'),
            onPressed: () => _suggest(context, ref),
          ),
        ),
    ]);
  }
}
