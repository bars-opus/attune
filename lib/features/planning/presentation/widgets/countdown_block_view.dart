import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_days_count.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:gap/gap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';
import 'planning_block_picker.dart';

/// "12 days", "Tomorrow", "Today" — counted on this device's calendar.
String planningCountdownLabel(DateTime target, DateTime today) {
  final days =
      DateUtils.dateOnly(target).difference(DateUtils.dateOnly(today)).inDays;
  return switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    > 1 => '$days days',
    -1 => 'Yesterday',
    _ => '${-days} days ago',
  };
}

class CountdownBlockView extends ConsumerWidget {
  const CountdownBlockView({
    super.key,
    required this.args,
    required this.block,
    required this.detail,
  });
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final PlanningEntryDetail detail;

  /// Which Date block it counts to, from the app's sheet. The rest of the
  /// payload (its title) is kept.
  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    List<PlanningBlock> dates,
  ) async {
    final picked = await pickPlanningLink(
      context,
      title: 'Count to',
      current: block.countdownDateBlockId,
      options: [
        for (final d in dates)
          PlanningLinkOption(
            id: d.id,
            title: d.title ?? 'Date',
            subtitle: formatPlanningRange(d.dateStart, d.dateEnd),
            icon: Icons.event_rounded,
          ),
      ],
    );
    if (picked == null ||
        picked == block.countdownDateBlockId ||
        !context.mounted)
      return;
    try {
      await ref.read(planningEntryProvider(args).notifier).updateBlockPayload(
        block,
        {...block.payload, 'date_block_id': picked},
      );
    } on PlanningStaleVersion {
      if (context.mounted)
        context.showInfoSnackbar(
          'Your partner just changed the countdown. Showing theirs.',
        );
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = block.countdownTarget;
    final dates = [
      for (final b in detail.blocks)
        if (b.type == PlanningBlockType.date && b.dateStart != null) b,
    ];
    final counted =
        dates.where((d) => d.id == block.countdownDateBlockId).firstOrNull;
    final waitingOnPoll = detail.blocks.any(
      (b) => b.type == PlanningBlockType.datePoll,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(block.title ?? 'Countdown', style: theme.textTheme.titleMedium),
        const Gap(Spacing.md),
        if (target == null) ...[
          Text(
            'Pick a date',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.outline,
            ),
          ),
          Text(
            waitingOnPoll
                ? 'Lock a date in the poll and the countdown starts.'
                : 'Add a date to this plan and the countdown starts.',
            style: TextStyle(color: scheme.outline),
          ),
        ] else ...[
          // Like the couple's days-together count: the number big, "days"
          // over "to go" (or "ago"); on the day itself, Today.
          () {
            final days =
                DateUtils.dateOnly(
                  target,
                ).difference(DateUtils.dateOnly(DateTime.now())).inDays;
            if (days == 0) {
              return Text(
                'Today',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              );
            }
            return AppDaysCount(
              count: days.abs(),
              top: days.abs() == 1 ? 'day' : 'days',
              bottom: days > 0 ? 'to go' : 'ago',
              roll: true,
            );
          }(),
          const Gap(Spacing.xs),
          Text(
            DateFormat.yMMMMEEEEd().format(target),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
        // What it counts to; with more than one date, tap to choose another.
        if (counted != null) ...[
          const Gap(Spacing.sm),
          InfoRowWidget(
            icon: Icons.event_rounded,
            showAvatar: false,
            iconSize: 20,
            iconColor: scheme.primary,
            title: 'Counts to: ${counted.title ?? 'Date'}',
            subtitle: '',
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            showDivider: false,
            showTrailingArrow: dates.length > 1,
            disableTrailing: dates.length < 2,
            onTap:
                dates.length > 1 ? () => _pickDate(context, ref, dates) : null,
          ),
        ],
      ],
    );
  }
}
