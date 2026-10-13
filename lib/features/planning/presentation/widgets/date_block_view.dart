import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/app_countdown.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

class DateBlockView extends ConsumerWidget {
  const DateBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    DateTime? start,
    DateTime? end,
  ) async {
    try {
      await ref
          .read(planningEntryProvider(args).notifier)
          .setDate(block, start, end);
    } on PlanningStaleVersion {
      if (context.mounted) {
        context.showInfoSnackbar('Your partner just changed this date. Showing theirs.');
      }
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<void> _pickSingle(BuildContext context, WidgetRef ref) async {
    // Saved once, when the wheel's sheet closes, not on every turn.
    final d = await pickPlanningDate(context, initial: block.dateStart);
    if (!context.mounted) return;
    final unchanged = block.dateStart != null && block.dateEnd == null && DateUtils.isSameDay(d, block.dateStart);
    if (!unchanged) await _set(context, ref, d, null);
  }

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (r != null && context.mounted) {
      await _set(context, ref, r.start, r.end == r.start ? null : r.end);
    }
  }

  /// The choices, as Settings-style rows. [onChoose] gets which one.
  List<Widget> _choices(
    BuildContext context, {
    required bool withRemove,
    required void Function(_DateChoice) onChoose,
  }) => [
    InfoRowWidget(
      icon: Icons.today_rounded,
      showAvatar: false,
      iconSize: 20.h,
      iconColor: Theme.of(context).colorScheme.primary,
      title: 'A single date',
      subtitle: '',
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      showDivider: true,
      showTrailingArrow: true,
      onTap: () => onChoose(_DateChoice.single),
    ),
    InfoRowWidget(
      iconSize: 20.h,
      icon: Icons.date_range_rounded,
      showAvatar: false,
      iconColor: Theme.of(context).colorScheme.primary,
      title: 'A start and an end date',
      subtitle: '',
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      showDivider: withRemove, // Remove follows it
      showTrailingArrow: true,
      onTap: () => onChoose(_DateChoice.range),
    ),
    if (withRemove)
      InfoRowWidget(
        icon: Icons.event_busy_rounded,
        showAvatar: false,
        iconSize: 20.h,
        iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
        title: 'Remove the date',
        subtitle: '',
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        showDivider: false,
        disableTrailing: true,
        onTap: () => onChoose(_DateChoice.remove),
      ),
  ];

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    _DateChoice choice,
  ) => switch (choice) {
    _DateChoice.single => _pickSingle(context, ref),
    _DateChoice.range => _pickRange(context, ref),
    _DateChoice.remove => _set(context, ref, null, null),
  };

  /// A date is set: the choices live in the app's bottom sheet, opened by
  /// the edit icon beside the date.
  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final choice =
        await BottomSheetUtils.showDocumentationBottomSheet<_DateChoice>(
          context: context,
          showButtons: false,
          maxHeight: 300.h,
          // Scrolls rather than overflows with large text sizes.
          widget: Builder(
            builder:
                (sheet) => SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BottomSheetHeader(title: ''),
                      const Gap(Spacing.sm),
                      const AppDivider(),
                      const Gap(Spacing.sm),
                      ..._choices(
                        sheet,
                        withRemove: true,
                        onChoose: (c) => Navigator.of(sheet).pop(c),
                      ),
                    ],
                  ),
                ),
          ),
        );
    if (choice != null && context.mounted) await _apply(context, ref, choice);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // A date is set: it sits in the note like a line of text — the date in
    // the primary colour (tap it to change or remove it), its countdown
    // below. The page shows it without a card or heading.
    if (block.dateStart != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            hint: 'Change or remove the date',
            child: InkWell(
              borderRadius: BorderRadius.circular(BorderRadiusTokens.sm),
              onTap: () => _edit(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Text(
                  formatPlanningRange(block.dateStart, block.dateEnd),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          // Counts down to the date (or through a range), live.
          AppCountdown.toDate(
            start: block.dateStart!,
            end: block.dateEnd,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No date yet: the heading itself asks for one (no separate line).
        Text(
          block.title ?? 'Pick a date',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w400),
        ),
        // heading, then the choices
        const Gap(Spacing.sm),
        const AppDivider(),
        const Gap(Spacing.sm),
        ..._choices(
          context,
          withRemove: false,
          onChoose: (c) => _apply(context, ref, c),
        ),
      ],
    );
  }
}

enum _DateChoice { single, range, remove }
