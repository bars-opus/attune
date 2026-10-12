import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/planning_models.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

/// "12 days", "Tomorrow", "Today" — counted on this device's calendar.
String planningCountdownLabel(DateTime target, DateTime today) {
  final days = DateUtils.dateOnly(target).difference(DateUtils.dateOnly(today)).inDays;
  return switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    > 1 => '$days days',
    -1 => 'Yesterday',
    _ => '${-days} days ago',
  };
}

class CountdownBlockView extends ConsumerWidget {
  const CountdownBlockView({super.key, required this.args, required this.block, required this.detail});
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final PlanningEntryDetail detail;

  /// Lets the couple pick which Date block to count to when there are several.
  Future<void> _pickDate(BuildContext context, WidgetRef ref, List<PlanningBlock> dates) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final d in dates)
            ListTile(
              leading: const Icon(Icons.event_rounded),
              title: Text(d.title ?? 'Date'),
              subtitle: Text(formatPlanningRange(d.dateStart, d.dateEnd)),
              onTap: () => Navigator.pop(c, d.id),
            ),
        ]),
      ),
    );
    if (picked == null || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).updateBlockPayload(block, {
        if (block.title != null) 'title': block.title,
        'date_block_id': picked,
      });
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = block.countdownTarget;
    final dates = [for (final b in detail.blocks) if (b.type == PlanningBlockType.date && b.dateStart != null) b];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(block.title ?? 'Countdown', style: theme.textTheme.titleMedium),
      const SizedBox(height: Spacing.xs),
      if (target == null) ...[
        Text('Pick a date', style: theme.textTheme.headlineSmall?.copyWith(color: scheme.outline)),
        Text('Add a date to this plan and the countdown starts.', style: TextStyle(color: scheme.outline)),
      ] else ...[
        Text(planningCountdownLabel(target, DateTime.now()),
            style: theme.textTheme.displaySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
        Text(DateFormat.yMMMMEEEEd().format(target), style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
      if (dates.length > 1)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => _pickDate(context, ref, dates), child: const Text('Count to another date')),
        ),
    ]);
  }
}
