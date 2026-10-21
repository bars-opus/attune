import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../../domain/code_point_limit.dart';
import '../../domain/goal_pace.dart';
import '../../domain/planning_money.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';
import 'planning_block_picker.dart';
import 'planning_progress_bar.dart';
import 'planning_rolling_amount.dart';

/// The pace line in two parts — its lead (bold) and the rest — or null
/// when there's nothing to say (no date, nothing to do, or reached).
(String, String)? _paceLine(PlanningProgress p, String defaultCurrency) {
  final pace = planningGoalPace(
    done: p.isChecklist ? p.done : p.current,
    total: p.isChecklist ? p.total : (p.target ?? 0),
    startedOn: p.startedOn,
    targetDate: p.targetDate,
    today: DateTime.now(),
  );
  String qty(int n) => p.isChecklist
      ? '$n ${n == 1 ? 'step' : 'steps'}'
      : (p.isMoney ? formatPlanningMoney(n, p.currency ?? defaultCurrency) : '$n');
  return switch (pace) {
    null || PaceReached() => null,
    PaceNotStarted() => (
        p.isChecklist ? 'Tick off a first step' : 'Add a first amount',
        'to see your pace',
      ),
    PaceOverdue() => ('The date has passed', 'pick a new one when you\'re ready'),
    PaceDueToday(:final left) => ('The date is today', '${qty(left)} to go'),
    PaceOnTrack(:final by) => ('On track', 'for ${MyDateFormat.toDateShort(by)}'),
    PaceAhead(:final finish) => ('Ahead of pace', 'done by ${MyDateFormat.toDateShort(finish)} at this rate'),
    PaceBehind(:final amount, :final perDay) => (
        'A little behind',
        'about ${qty(amount)} a ${perDay ? 'day' : 'week'} would get you there',
      ),
  };
}

/// Will we make it? A goal's pace line — "On track" over "for Fri, 12 Dec",
/// "A little behind" over "about 2 steps a week…" — gentle, and about the
/// two of you. Shown above the goal's card; nothing when there's nothing to
/// say (no date, nothing to do, or reached).
class PlanningGoalPaceLine extends StatelessWidget {
  const PlanningGoalPaceLine({super.key, required this.block, required this.defaultCurrency});
  final PlanningBlock block;
  final String defaultCurrency;

  @override
  Widget build(BuildContext context) {
    final p = block.progress;
    final line = p == null ? null : _paceLine(p, defaultCurrency);
    if (line == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // The verdict on its own line, then the detail; room before the card.
    return Padding(
      padding: const EdgeInsets.only(left: Spacing.xs, bottom: Spacing.md),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: line.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: '\n${line.$2}'),
        ]),
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// The couple's progress toward a goal: contributions toward a target
/// (money or a count), or how much of a checklist is done.
class ProgressBlockView extends ConsumerWidget {
  const ProgressBlockView({super.key, required this.args, required this.block, required this.defaultCurrency});
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final String defaultCurrency;

  String _amount(PlanningProgress p, int v) =>
      p.isMoney ? formatPlanningMoney(v, p.currency ?? defaultCurrency) : '$v';

  Future<void> _add(BuildContext context, WidgetRef ref, PlanningProgress p) async {
    final fields = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AmountDialog(
          title: 'Add to it', label: 'Amount', action: 'Add', withNote: true, example: 50,
          currency: p.isMoney ? (p.currency ?? defaultCurrency) : null),
    );
    if (fields == null || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).saveRichItem(block.id, fields: fields);
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<void> _setTarget(BuildContext context, WidgetRef ref, PlanningProgress p) async {
    final currency = p.isMoney ? (p.currency ?? defaultCurrency) : null;
    final fields = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AmountDialog(title: 'Set the target', label: 'Target', action: 'Save', currency: currency, example: 1000),
    );
    if (fields == null || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).setTarget(block, fields['amount_minor'] as int, currency);
    } on PlanningStaleVersion {
      if (context.mounted) {
        context.showInfoSnackbar('Your partner just changed the target. Showing theirs.');
      }
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  /// Which checklist it tracks, from the app's sheet. The rest of the
  /// payload (mode, title) is kept.
  Future<void> _pickChecklist(BuildContext context, WidgetRef ref, List<PlanningBlock> lists) async {
    final current = block.progress!.checklistBlockId;
    final picked = await pickPlanningLink(
      context,
      title: 'Track',
      current: current,
      options: [
        for (final l in lists)
          PlanningLinkOption(
            id: l.id,
            title: l.title ?? 'Checklist',
            subtitle: l.items.isEmpty ? 'No steps yet' : '${l.items.length} steps',
            icon: Icons.checklist_rounded,
          ),
      ],
    );
    if (picked == null || picked == current || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).updateBlockPayload(block, {
        ...block.payload,
        'checklist_block_id': picked,
      });
    } on PlanningStaleVersion {
      if (context.mounted) context.showInfoSnackbar('Your partner just changed the progress. Showing theirs.');
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  /// Which Date block it's due by, from the app's sheet. The rest of the
  /// payload (mode, checklist) is kept.
  Future<void> _pickDate(BuildContext context, WidgetRef ref, List<PlanningBlock> dates) async {
    final current = block.progress!.dateBlockId;
    final picked = await pickPlanningLink(
      context,
      title: 'Due by',
      current: current,
      options: [
        for (final d in dates)
          PlanningLinkOption(
            id: d.id,
            title: d.title ?? 'Date',
            subtitle: d.dateStart == null ? 'No date yet' : formatPlanningRange(d.dateStart, d.dateEnd),
            icon: Icons.event_rounded,
          ),
      ],
    );
    if (picked == null || picked == current || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).updateBlockPayload(block, {
        ...block.payload,
        'date_block_id': picked,
      });
    } on PlanningStaleVersion {
      if (context.mounted) context.showInfoSnackbar('Your partner just changed the progress. Showing theirs.');
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, PlanningItem item) async {
    final ctl = ref.read(planningEntryProvider(args).notifier);
    final index = block.items.indexOf(item);
    try {
      await ctl.deleteItem(block.id, item.id);
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
      return;
    }
    if (!context.mounted) return;
    context.showInfoSnackbar('Removed',
        actionLabel: 'Undo', onAction: () => ctl.restoreItem(block.id, item.id, index: index));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = block.progress!;
    final lists = [
      for (final b in ref.watch(planningEntryProvider(args)).valueOrNull?.blocks ?? const <PlanningBlock>[])
        if (b.type == PlanningBlockType.checklist) b,
    ];
    final tracked = lists.where((l) => l.id == p.checklistBlockId).firstOrNull;
    final dates = [
      for (final b in ref.watch(planningEntryProvider(args)).valueOrNull?.blocks ?? const <PlanningBlock>[])
        if (b.type == PlanningBlockType.date) b,
    ];
    final dueBy = dates.where((d) => d.id == p.dateBlockId).firstOrNull;
    final summary = p.isChecklist
        ? (p.total == 0 ? 'Add steps to a checklist in this plan' : '${p.done} of ${p.total} done')
        : (p.target == null ? '${_amount(p, p.current)} so far' : '${_amount(p, p.current)} of ${_amount(p, p.target!)}');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(block.title ?? 'Progress', style: theme.textTheme.titleMedium),
      const Gap(Spacing.sm),
      Semantics(
        label: '$summary, ${(p.fraction * 100).round()} percent',
        excludeSemantics: true,
        // A few steps: a segment each. Many, or an amount: one smooth bar
        // (an amount with quarter marks).
        child: PlanningProgressBar(
          fraction: p.fraction,
          segments: p.isChecklist && p.total >= 2 && p.total <= 12 ? p.total : null,
          milestones: p.isMoney,
        ),
      ),
      const Gap(Spacing.xs),
      Row(children: [
        // The figure so far rolls up as the block shows; the rest of the line
        // is its tail ("of GHS 1,000.00", "of 12 done").
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: p.isChecklist
                ? (p.total == 0 ? Text(summary) : PlanningRollingCount(count: p.done, suffix: ' of ${p.total} done'))
                : p.isMoney
                    ? PlanningRollingMoney(
                        minor: p.current,
                        currency: p.currency ?? defaultCurrency,
                        suffix: p.target == null ? ' so far' : ' of ${_amount(p, p.target!)}',
                      )
                    : PlanningRollingCount(
                        count: p.current,
                        suffix: p.target == null ? ' so far' : ' of ${_amount(p, p.target!)}',
                      ),
          ),
        ),
        if (p.isComplete)
          Text('Reached 🎉', style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
      ]),
      // The date it's due by; with more than one, tap to choose another. Its
      // pace line ("On track…") sits above the card (PlanningGoalPaceLine).
      if (dueBy != null) ...[
        const Gap(Spacing.md),
        InfoRowWidget(
          icon: Icons.event_rounded,
          showAvatar: false,
          iconSize: 20,
          iconColor: scheme.primary,
          title: 'By: ${dueBy.title ?? 'Date'}',
          subtitle: dueBy.dateStart == null ? 'No date yet' : formatPlanningRange(dueBy.dateStart, null),
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          // Marks it off from Tracks (and contributions) under it.
          showDivider: true,
          showTrailingArrow: dates.length > 1,
          disableTrailing: dates.length < 2,
          onTap: dates.length > 1 ? () => _pickDate(context, ref, dates) : null,
        ),
      ],
      // Each contribution, newest last; swipe right to take one back.
      if (!p.isChecklist)
        for (final item in block.items)
          Dismissible(
            key: ValueKey('contribution-${item.id}'),
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
              await _delete(context, ref, item);
              return false;
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(children: [
                Expanded(
                  child: Text(item.text.isEmpty ? 'Added' : item.text,
                      style: TextStyle(color: item.text.isEmpty ? scheme.outline : null)),
                ),
                Text('+${_amount(p, item.amountMinor ?? 0)}', style: theme.textTheme.bodyLarge),
              ]),
            ),
          ),
      // What it tracks; with more than one checklist, tap to choose another.
      if (p.isChecklist && tracked != null) ...[
        const Gap(Spacing.sm),
        InfoRowWidget(
          icon: Icons.checklist_rounded,
          showAvatar: false,
          iconSize: 20,
          iconColor: scheme.primary,
          title: 'Tracks: ${tracked.title ?? 'Checklist'}',
          subtitle: '',
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          showDivider: false,
          showTrailingArrow: lists.length > 1,
          disableTrailing: lists.length < 2,
          onTap: lists.length > 1 ? () => _pickChecklist(context, ref, lists) : null,
        ),
      ],
      if (!p.isChecklist)
        Wrap(spacing: Spacing.sm, children: [
          TextButton.icon(
              icon: const Icon(Icons.add_rounded), label: const Text('Add to it'), onPressed: () => _add(context, ref, p)),
          TextButton(onPressed: () => _setTarget(context, ref, p), child: const Text('Set target')),
        ]),
    ]);
  }
}

/// Returns {'amount_minor': int, 'label'?: String} or null when cancelled.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.label,
    required this.action,
    required this.currency,
    this.withNote = false,
    this.example = 0,
  });
  final String title;
  final String label;
  final String action;
  final String? currency; // null = a whole-number count

  /// The figure the empty amount field suggests ("50.00", "1,000.00").
  final int example;
  final bool withNote;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _parsed {
    final c = widget.currency;
    if (c != null) return parsePlanningMoney(_amount.text, c);
    final n = int.tryParse(_amount.text.trim());
    return n == null || n < 0 || n > planningMaxMinor ? null : n;
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    final valid = parsed != null && parsed > 0;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        AppTextFormField(
          controller: _amount,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: widget.currency != null),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(widget.currency != null ? r'[0-9.,]' : r'[0-9]'))],
          label: widget.label,
          hintText: widget.currency == null
              ? '${widget.example}'
              : planningMoneyHint(widget.currency!, widget.example),
          suffixText: widget.currency,
          onChanged: (_) => setState(() {}),
        ),
        if (widget.withNote)
          AppTextFormField(
            controller: _note,
            label: 'Note (optional)',
            hintText: 'Birthday money',
            textInputAction: TextInputAction.done,
            inputFormatters: [CodePointLengthFormatter(120)],
          ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, <String, dynamic>{
                    'amount_minor': _parsed,
                    if (_note.text.trim().isNotEmpty) 'label': _note.text.trim(),
                  })
              : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}
