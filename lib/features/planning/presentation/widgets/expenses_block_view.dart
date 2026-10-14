import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/core/ui/motion/animated_keyed_column.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/charts/app_pie_chart.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../../domain/expense_view.dart';
import '../../domain/code_point_limit.dart';
import '../../domain/planning_money.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

/// Currencies offered first in the expense editor; the plan's own currency
/// is always included.
const planningCommonCurrencies = [
  'GHS',
  'NGN',
  'KES',
  'ZAR',
  'USD',
  'EUR',
  'GBP',
  'CAD',
  'AUD',
  'JPY',
  'IDR',
];

/// Expense lines: what for, how much, who paid. Totals per currency; with
/// split on, each line can carry the other partner's share.
/// How this device shows each Expenses block (sort and partner filter),
/// kept while the app is open. Set from the block's ⋮ menu.
final planningExpenseViewProvider =
    StateProvider.family<PlanningExpenseView, String>(
      (ref, blockId) => const PlanningExpenseView(),
    );

/// Minor units in one whole unit of [currency] (100 for GHS, 1 for JPY).
int _wholeUnit(String currency) {
  var n = 1;
  for (var d = planningCurrencyDigits(currency); d > 0; d--) {
    n *= 10;
  }
  return n;
}

class ExpensesBlockView extends ConsumerWidget {
  const ExpensesBlockView({
    super.key,
    required this.args,
    required this.block,
    required this.detail,
  });
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final PlanningEntryDetail detail;

  /// The sheet stays open until the save succeeds, and a new line keeps one
  /// id for the whole sheet, so a retry after a dropped response can't
  /// save the same money twice (checklist 2.18).
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    PlanningItem? item,
  ) async {
    final ctl = ref.read(planningEntryProvider(args).notifier);
    await BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      // Neutral, so the fields stand out against it.
      backgroundColor: Theme.of(context).colorScheme.neutral,
      widget: ExpenseEditor(
        item: item,
        members: detail.members,
        me: ref.read(planningCurrentUserIdProvider),
        defaultCurrency: detail.entry.currency,
        splitOn: detail.entry.split != null,
        save: (fields, id) async {
          try {
            await ctl.saveRichItem(
              block.id,
              existing: item,
              id: id,
              fields: fields,
            );
            return null;
          } on PlanningStaleVersion {
            context.showInfoSnackbar(
              'Your partner just changed this expense. Showing theirs.',
            );
            return null;
          } catch (e) {
            return planningErrorMessage(mapPlanningError(e));
          }
        },
      ),
    );
  }

  /// Paid lines stay in the list, struck through, and count toward what's
  /// paid rather than what's left. Shared: the partner sees it too.
  Future<void> _togglePaid(
    BuildContext context,
    WidgetRef ref,
    PlanningItem item,
  ) async {
    try {
      await ref
          .read(planningEntryProvider(args).notifier)
          .setChecked(block.id, item, !item.isChecked);
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlanningItem item,
  ) async {
    final ctl = ref.read(planningEntryProvider(args).notifier);
    final index = block.items.indexOf(item);
    try {
      await ctl.deleteItem(block.id, item.id);
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
      return;
    }
    if (!context.mounted) return;
    context.showInfoSnackbar(
      'Removed ${item.text}',
      actionLabel: 'Undo',
      onAction: () => ctl.restoreItem(block.id, item.id, index: index),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final view = ref.watch(planningExpenseViewProvider(block.id));
    final rows = planningExpenseRows(block.items, view);
    final totals = planningExpenseTotals(rows);
    // What's left of the plan's budget, for the chart's last slice.
    final budget =
        detail.blocks
            .where(
              (b) =>
                  b.type == PlanningBlockType.budget && b.targetMinor != null,
            )
            .firstOrNull;
    final chart = planningExpenseChart(
      rows,
      budgetLeft:
          budget == null
              ? null
              : (
                minor: budget.targetMinor! - (budget.budget?.spentMinor ?? 0),
                currency: budget.targetCurrency ?? detail.entry.currency,
              ),
    );
    String money(int Function(({int total, int paid}) t) pick) => totals.entries
        .map((e) => formatPlanningMoney(pick(e.value), e.key))
        .join(' · ');
    final anyPaid = totals.values.any((t) => t.paid > 0);
    final allPaid =
        totals.isNotEmpty && totals.values.every((t) => t.paid == t.total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(block.title ?? 'Expenses', style: theme.textTheme.titleMedium),
        const Gap(Spacing.lg),
        if (chart != null) ...[
          // What the money went on at a glance, one solid colour per wedge:
          // paid, not yet paid, and what's left of the budget. Follows the sort
          // and filter.
          Center(
            child: LayoutBuilder(
              builder:
                  (context, c) => AppPieChart(
                    size: c.maxWidth.clamp(0, 260).toDouble(),
                    semanticLabel: 'Spending by expense in ${chart.currency}',
                    slices: [
                      for (final s in chart.slices)
                        PieSlice(
                          label: s.label,
                          value: s.value,
                          valueLabel: formatPlanningMoneyCompact(
                            (s.value * _wholeUnit(chart.currency)).round(),
                            chart.currency,
                          ),
                          color: switch (s.kind) {
                            PlanningChartSlice.paid => scheme.primary,
                            PlanningChartSlice.unpaid => scheme.primary
                                .withValues(alpha: 0.18),
                            PlanningChartSlice.left =>
                              scheme.outlineVariant, // visible on the card
                          },
                          textColor: switch (s.kind) {
                            PlanningChartSlice.paid => scheme.onPrimary,
                            PlanningChartSlice.unpaid => scheme.primary,
                            PlanningChartSlice.left => scheme.onSurface,
                          },
                        ),
                    ],
                  ),
            ),
          ),
          const Gap(Spacing.lg),
          // Full width, so the key centres under the chart.
          SizedBox(
            width: double.infinity,
            child: Wrap(
            alignment: WrapAlignment.center,
            spacing: Spacing.md,
            runSpacing: Spacing.xs,
            children: [
              _LegendDot(color: scheme.primary, label: 'Paid'),
              _LegendDot(
                color: scheme.primary.withValues(alpha: 0.18),
                label: 'Not yet paid',
              ),
              if (chart.slices.any((s) => s.kind == PlanningChartSlice.left))
                _LegendDot(
                  color: scheme.outlineVariant,
                  label: 'Left in budget',
                ),
            ],
          ),
          ),
          if (chart.otherCurrencies)
            Center(
              child: Text(
                'In ${chart.currency}; other currencies aren\'t shown',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                ),
              ),
            ),
          // The chart's key, then the expenses.
          const Gap(Spacing.xl),
          const AppDivider(),
          const Gap(Spacing.sm),
        ],
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Text(
              block.items.isEmpty
                  ? 'Nothing spent yet.'
                  : 'Nothing paid by ${planningMemberName(detail.members, view.paidBy)} yet.',
              style: TextStyle(color: scheme.outline),
            ),
          ),
        // Names the columns: Item over the names (past the initials), Price over
        // the amounts.
        if (rows.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 45.h + Spacing.md.w,
                ), // InfoRowWidget's leading slot and gap
                Expanded(
                  child: Text(
                    'Items',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  'Prices',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const AppDivider(),
        ],
        // Lines grow in, fade out and glide to their new place when added,
        // removed, put back, sorted or filtered.
        AnimatedKeyedColumn(
          children: [
            for (final item in rows)
              // A line and the divider under it move together; none under the last.
              KeyedSubtree(
                key: ValueKey('expense-line-${item.id}'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Dismissible(
                      key: ValueKey('expense-${item.id}'),
                      // Swipe right = delete, as everywhere in Planning; swipe left = paid / unpaid.
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: Spacing.horizontalMd,
                        color: scheme.errorContainer,
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                      secondaryBackground: Container(
                        alignment: Alignment.centerRight,
                        padding: Spacing.horizontalMd,
                        color:
                            item.isChecked
                                ? scheme.surfaceContainerHighest
                                : scheme.primaryContainer,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.isChecked
                                  ? 'Mark as unpaid'
                                  : 'Mark as paid',
                              style: TextStyle(
                                color:
                                    item.isChecked
                                        ? scheme.onSurfaceVariant
                                        : scheme.onPrimaryContainer,
                              ),
                            ),
                            const Gap(Spacing.sm),
                            Icon(
                              item.isChecked
                                  ? Icons.undo_rounded
                                  : Icons.check_circle_outline_rounded,
                              color:
                                  item.isChecked
                                      ? scheme.onSurfaceVariant
                                      : scheme.onPrimaryContainer,
                            ),
                          ],
                        ),
                      ),
                      // The delete takes the row away itself (and puts it back if it fails),
                      // so the swipe never leaves a dismissed widget in the tree.
                      confirmDismiss: (direction) async {
                        if (direction == DismissDirection.endToStart) {
                          await _togglePaid(context, ref, item);
                        } else {
                          await _delete(context, ref, item);
                        }
                        return false;
                      },
                      child: MergeSemantics(
                        // One node per line, so the actions below are offered on the row itself.
                        child: Semantics(
                          // The swipes, for people who can't swipe.
                          customSemanticsActions: {
                            CustomSemanticsAction(
                                  label:
                                      item.isChecked
                                          ? 'Mark as unpaid'
                                          : 'Mark as paid',
                                ):
                                () => _togglePaid(context, ref, item),
                            const CustomSemanticsAction(label: 'Delete'):
                                () => _delete(context, ref, item),
                          },
                          // The app's standard row; the full-width divider between lines
                          // comes from the list, not the row.
                          child: InfoRowWidget(
                            title: item.text,
                            // InfoRowWidget's title, at normal weight.
                            titleStyle: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.onSurface,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                            ),
                            subtitle: '',

                            titleMaxLines: 2,
                            showDivider: false,
                            onTap: () => _edit(context, ref, item),
                            leadingWidget: Semantics(
                              label:
                                  'Paid by ${planningMemberName(detail.members, item.paidBy)}',
                              excludeSemantics: true,
                              child: CircleAvatar(
                                radius: 14,
                                // Light primary until paid, then primary: the chart's colours.
                                backgroundColor:
                                    item.isChecked
                                        ? scheme.primary
                                        : scheme.primary.withValues(
                                          alpha: 0.18,
                                        ),
                                child: Text(
                                  detail.member(item.paidBy)?.initial ?? '?',
                                  style: TextStyle(
                                    fontSize: 12.h,
                                    color:
                                        item.isChecked
                                            ? scheme.onPrimary
                                            : scheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            trailing:
                                item.amountMinor != null &&
                                        item.currency != null
                                    ? Text(
                                      formatPlanningMoney(
                                        item.amountMinor!,
                                        item.currency!,
                                      ),
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                        // A paid amount is struck through and no longer counts toward what's left.
                                        decoration:
                                            item.isChecked
                                                ? TextDecoration.lineThrough
                                                : null,
                                        color:
                                            item.isChecked
                                                ? scheme.outline
                                                : null,
                                      ),
                                    )
                                    : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                    if (item.id != rows.last.id)
                      const AppDivider(padding: EdgeInsets.all(0)),
                  ],
                ),
              ),
          ],
        ),
        if (totals.isNotEmpty) ...[
          const Gap(Spacing.xs),
          const AppDivider(),
          // Filtered to one partner, the totals are just theirs, and say so.
          if (view.paidBy != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Text(
                'Paid by ${planningMemberName(detail.members, view.paidBy)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          // The subtotals once anything is paid, then the total: the app's
          // rows, amounts under Prices.
          if (anyPaid && !allPaid) ...[
            _TotalRow(
              icon: Icons.check_circle_outline_rounded,
              title: 'Paid',
              emphasis: true,
              amount: money((t) => t.paid),
              amountColor: scheme.primary,
            ),
            AppDivider(),
            _TotalRow(
              icon: Icons.schedule_rounded,
              title: 'Left to pay',
              amount: money((t) => t.total - t.paid),
              amountColor: scheme.error,
              emphasis: true,
            ),
          ],
          AppDivider(),
          _TotalRow(
            icon: Icons.receipt_long_outlined,
            title: 'Total',
            subtitle: allPaid ? 'All paid' : '',
            amount: money((t) => t.total),
            emphasis: !anyPaid || allPaid,
            bold: true,
          ),
          // The totals, then Add expense.
          const Gap(Spacing.sm),
          const AppDivider(),
          const Gap(Spacing.sm),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add expense'),
            onPressed: () => _edit(context, ref, null),
          ),
        ),
      ],
    );
  }
}

/// Saves through [save], which returns null when done (the sheet closes)
/// or a message to show while the sheet stays open for a retry.
class ExpenseEditor extends StatefulWidget {
  const ExpenseEditor({
    super.key,
    required this.item,
    required this.members,
    required this.me,
    required this.defaultCurrency,
    required this.splitOn,
    required this.save,
  });
  final Future<String?> Function(Map<String, dynamic> fields, String id) save;
  final PlanningItem? item;
  final List<PlanningMember> members;
  final String? me;
  final String defaultCurrency;
  final bool splitOn;

  @override
  State<ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<ExpenseEditor> {
  late final _label = TextEditingController(text: widget.item?.text ?? '');
  late final _amount = TextEditingController(
    text: _initialAmount(widget.item?.amountMinor),
  );
  late final _share = TextEditingController(
    text: _initialAmount(widget.item?.splitShareMinor),
  );
  late String _currency = widget.item?.currency ?? widget.defaultCurrency;
  late String? _paidBy = widget.item?.paidBy ?? widget.me;
  late bool _equal = widget.item?.splitShareMinor == null;
  late final String _id = widget.item?.id ?? const Uuid().v4();
  bool _saving = false;
  String? _error;

  /// Set once Done is tapped with something missing, so its field says what.
  bool _tried = false;

  Future<void> _submit() async {
    if (_saving) return; // Done again while the first save is in flight
    if (!_valid) {
      setState(() => _tried = true);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.save(<String, dynamic>{
      'label': _label.text.trim(),
      'amount_minor': _amountMinor,
      'currency': _currency,
      'paid_by': _paidBy,
      'split_share_minor': _shareMinor,
    }, _id);
    if (!mounted) return;
    if (error == null) {
      popPlanningSheet(context);
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  String _initialAmount(int? minor) {
    if (minor == null) return '';
    final digits = planningCurrencyDigits(
      widget.item?.currency ?? widget.defaultCurrency,
    );
    if (digits == 0) return '$minor';
    final s = minor.toString().padLeft(digits + 1, '0');
    return '${s.substring(0, s.length - digits)}.${s.substring(s.length - digits)}';
  }

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    _share.dispose();
    super.dispose();
  }

  int? get _amountMinor => parsePlanningMoney(_amount.text, _currency);
  int? get _shareMinor =>
      _equal ? null : parsePlanningMoney(_share.text, _currency);

  bool get _valid =>
      _label.text.trim().isNotEmpty &&
      _amountMinor != null &&
      (_equal || (_shareMinor != null && _shareMinor! <= _amountMinor!));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelColor = scheme.onSurface.withValues(alpha: 0.6);
    final currencies =
        {
          widget.defaultCurrency,
          _currency,
          ...planningCommonCurrencies,
        }.toList();
    final labelError =
        _tried && _label.text.trim().isEmpty ? 'Say what it was for' : null;
    final amountError =
        _amount.text.isNotEmpty && _amountMinor == null
            ? 'Enter an amount like 12.50'
            : (_tried && _amount.text.trim().isEmpty
                ? 'Enter an amount'
                : null);
    final shareError =
        !_equal &&
                _tried &&
                (_shareMinor == null ||
                    (_amountMinor != null && _shareMinor! > _amountMinor!))
            ? 'Enter their share, up to the amount'
            : null;
    // Compact fields, with room for an error line only while there is one.
    double? height(String? error) =>
        error == null ? FormTokens.compactFieldHeight : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Done saves; something missing keeps the sheet open and its field says what.
        BottomSheetHeader(
            actionLabel: 'Save',
          title: widget.item == null ? 'Add expense' : 'Edit expense',
          onPressed: _submit,
        ),
        if (_saving) const LinearProgressIndicator(),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextFormField(
                  controller: _label,
                  autofocus: widget.item == null,
                  textCapitalization: TextCapitalization.sentences,
                  label: 'What for',
                  labelColor: labelColor,
                  height: height(labelError),
                  errorText: labelError,
                  inputFormatters: [CodePointLengthFormatter(120)],
                  onChanged: (_) => setState(() {}),
                ),
                const Gap(Spacing.sm),
                AppTextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  label: 'Amount',
                  labelColor: labelColor,
                  // The suffix holds the box at 48, so the currency sits centred in it.
                  height: amountError == null ? kMinInteractiveDimension : null,
                  errorText: amountError,
                  onChanged: (_) => setState(() {}),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: Spacing.sm),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _currency,
                        items: [
                          for (final c in currencies)
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged:
                            (c) => setState(() => _currency = c ?? _currency),
                      ),
                    ),
                  ),
                ),
                const Gap(Spacing.md),
                Text(
                  'Paid by',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: labelColor),
                ),
                const Gap(Spacing.xs),
                // The same segmented choice as the checklist's "Who's on it".
                SegmentedButton<String>(
                  segments: [
                    for (final m in widget.members)
                      ButtonSegment(
                        value: m.id,
                        label: Text(
                          m.id == widget.me
                              ? 'Me'
                              : (m.displayName.isEmpty
                                  ? 'Partner'
                                  : m.displayName),
                        ),
                      ),
                  ],
                  selected: {if (_paidBy != null) _paidBy!},
                  // Only before anyone is chosen (no "me" to default to).
                  emptySelectionAllowed: _paidBy == null,
                  onSelectionChanged: (s) {
                    if (s.isNotEmpty) setState(() => _paidBy = s.first);
                  },
                ),
                if (widget.splitOn) ...[
                  const Gap(Spacing.xs),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Split equally'),
                    value: _equal,
                    onChanged: (v) => setState(() => _equal = v),
                  ),
                  if (!_equal)
                    AppTextFormField(
                      controller: _share,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      label: "The other person's share",
                      labelColor: labelColor,
                      helperText:
                          shareError == null
                              ? 'What the one who did not pay owes'
                              : null,
                      errorText: shareError,
                      onChanged: (_) => setState(() {}),
                    ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const Gap(Spacing.xs),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

/// A line of an Expenses block's totals: the app's InfoRowWidget, with the
/// amount at the end, under Prices.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.icon,
    required this.title,
    required this.amount,
    this.subtitle = '',
    this.emphasis = false,
    this.amountColor,
    this.bold = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String amount;

  /// The figure that matters most: what's left to pay, or the total.
  final bool emphasis;

  /// Colours only the amount (with its currency); the title and icon keep
  /// theirs. Null keeps the usual text colour.
  final Color? amountColor;

  /// The amount in bold (the Total row).
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InfoRowWidget(
      icon: icon,
      iconSize: 0,
      title: title,
      titleFontSize: 12.h,

      subtitle: subtitle,
      showAvatar: false,
      showDivider: false,
      trailing: Text(
        amount,
        style: (emphasis
                ? theme.textTheme.titleSmall
                : theme.textTheme.bodyLarge)
            ?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: amountColor,
              fontWeight: bold ? FontWeight.bold : null,
            ),
      ),
    );
  }
}
