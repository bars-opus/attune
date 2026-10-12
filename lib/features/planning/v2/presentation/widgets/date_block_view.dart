import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_v2_error.dart';
import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';

class DateBlockView extends ConsumerWidget {
  const DateBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  Future<void> _set(BuildContext context, WidgetRef ref, DateTime? start, DateTime? end) async {
    try {
      await ref.read(planningV2EntryProvider(args).notifier).setDate(block, start, end);
    } on PlanningV2StaleVersion {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your partner just changed this date. Showing theirs.')));
      }
    } catch (e) {
      if (context.mounted) showPlanningV2Error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final first = DateTime(now.year - 5);
    final last = DateTime(now.year + 10);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(block.title ?? 'Date', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Spacing.xs),
      Text(formatPlanningRange(block.dateStart, block.dateEnd), style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: Spacing.sm),
      Wrap(spacing: Spacing.sm, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.today_rounded),
          label: const Text('One day'),
          onPressed: () async {
            final d = await showDatePicker(
                context: context, firstDate: first, lastDate: last, initialDate: block.dateStart ?? now);
            if (d != null && context.mounted) await _set(context, ref, d, null);
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_rounded),
          label: const Text('Range'),
          onPressed: () async {
            final r = await showDateRangePicker(context: context, firstDate: first, lastDate: last);
            if (r != null && context.mounted) {
              await _set(context, ref, r.start, r.end == r.start ? null : r.end);
            }
          },
        ),
        if (block.dateStart != null)
          TextButton(onPressed: () => _set(context, ref, null, null), child: const Text('Clear')),
      ]),
    ]);
  }
}
