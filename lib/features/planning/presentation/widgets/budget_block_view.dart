import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/app_tabs.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/charts/arc_gauge.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/app/theme/app_theme.dart';
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
import '../../domain/expense_view.dart';
import '../../domain/planning_money.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';
import 'planning_block_picker.dart';
import 'planning_rolling_amount.dart';
import 'planning_spend_chart.dart';

/// How a budget names what it counts, in its Counts row.
String planningBudgetSourceLabel(PlanningBlock source) =>
    source.type == PlanningBlockType.table
        ? '${source.title ?? 'Table'} (table)'
        : source.title ?? 'Expenses';

/// A target against what it counts — all of the plan's expense lines, one
/// Expenses block, or a table's money columns (its Counts row). Spent is
/// computed by the server; other currencies are shown, never converted.
class BudgetBlockView extends ConsumerWidget {
  const BudgetBlockView({
    super.key,
    required this.args,
    required this.block,
    required this.defaultCurrency,
  });
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final String defaultCurrency;

  String get _currency => block.targetCurrency ?? defaultCurrency;

  Future<void> _setTarget(BuildContext context, WidgetRef ref) async {
    final minor = await BottomSheetUtils.showDocumentationBottomSheet<int>(
      context: context,
      // Neutral, so the field stands out against it.
      backgroundColor: Theme.of(context).colorScheme.neutral,
      widget: _BudgetSheet(
        currency: _currency,
        initialMinor: block.targetMinor,
      ),
    );
    if (minor == null || !context.mounted) return;
    try {
      await ref
          .read(planningEntryProvider(args).notifier)
          .setTarget(block, minor, _currency);
    } on PlanningStaleVersion {
      if (context.mounted) {
        context.showInfoSnackbar(
          'Your partner just changed the budget. Showing theirs.',
        );
      }
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  /// Counts: all expenses, one Expenses block or a money table. The rest of
  /// the payload (its title) is kept.
  Future<void> _chooseSource(
    BuildContext context,
    WidgetRef ref,
    List<PlanningBlock> sources,
    String? current,
  ) async {
    final chosen = await pickPlanningLink(
      context,
      title: 'What it counts',
      sheetKey: const ValueKey('planning-budget-source-sheet'),
      current: current ?? '',
      options: [
        const PlanningLinkOption(
          id: '',
          title: 'All expenses',
          subtitle: 'Every expense in this plan',
          icon: Icons.receipt_long_outlined,
        ),
        for (final b in sources)
          PlanningLinkOption(
            id: b.id,
            title:
                b.title ??
                (b.type == PlanningBlockType.table ? 'Table' : 'Expenses'),
            subtitle:
                b.type == PlanningBlockType.table
                    ? 'Table - all its money columns'
                    : 'Expenses',
            icon:
                b.type == PlanningBlockType.table
                    ? Icons.table_chart_outlined
                    : Icons.payments_outlined,
          ),
      ],
    );
    if (chosen == null || chosen == (current ?? '') || !context.mounted) return;
    final payload = {...block.payload}..remove('source_block_id');
    if (chosen.isNotEmpty) payload['source_block_id'] = chosen;
    try {
      await ref
          .read(planningEntryProvider(args).notifier)
          .updateBlockPayload(block, payload);
    } on PlanningStaleVersion {
      if (context.mounted) {
        context.showInfoSnackbar(
          'Your partner just changed the budget. Showing theirs.',
        );
      }
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blocks =
        ref.watch(planningEntryProvider(args)).valueOrNull?.blocks ?? const [];
    final sources = [
      for (final b in blocks)
        if (PlanningEntryController.isBudgetSource(b)) b,
    ];
    final computed =
        block.budget ??
        const PlanningBudgetComputed(spentMinor: 0, otherCurrencies: []);
    // What the server really counted; a link to a deleted block reads as
    // all expenses, as it is counted.
    final counted =
        computed.source == PlanningBudgetSource.all
            ? null
            : blocks.where((b) => b.id == computed.sourceBlockId).firstOrNull;
    final target = block.targetMinor;
    final spent = computed.spentMinor;
    final over = target != null && spent > target;
    final chart = planningBudgetChart(
      block,
      blocks,
      planCurrency: defaultCurrency,
    );
    // Budget: the gauge, what it counts and Set budget. Breakdown: only the
    // chart of what it counts, and its key.
    final progress = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (target == null)
          PlanningRollingMoney(
            minor: spent,
            currency: _currency,
            prefix: 'No budget set. Spent so far: ',
            style: TextStyle(color: scheme.outline),
          )
        else ...[
          // What's left of the budget, as a gauge; red once it's over.
          Center(
            child: ArcGauge(
              fraction: target == 0 ? 1 : spent / target,
              over: over,
              headline:
                  over
                      ? '${formatPlanningMoney(spent - target, _currency)} over budget'
                      : '${formatPlanningMoney(target - spent, _currency)} left',
              // Rolls up with the arc as it fills.
              headlineBuilder:
                  (style) => PlanningRollingMoney(
                    minor: over ? spent - target : target - spent,
                    currency: _currency,
                    suffix: over ? ' over budget' : ' left',
                    style: style,
                    textAlign: TextAlign.center,
                  ),
              caption: 'of ${formatPlanningMoney(target, _currency)}',
              semanticLabel: 'Budget',
            ),
          ),
          Center(
            child: PlanningRollingMoney(
              minor: spent,
              currency: _currency,
              suffix: ' spent',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        if (computed.otherCurrencies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              'Also spent ${computed.otherCurrencies.map((o) => formatPlanningMoney(o.$2, o.$1)).join(' · ')} '
              '(not counted)',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ),
        const Gap(Spacing.md),
        InfoRowWidget(
          icon: Icons.filter_list_rounded,
          showAvatar: false,
          iconSize: 20,
          iconColor: scheme.primary,
          title:
              'Counts: ${counted == null ? 'All expenses' : planningBudgetSourceLabel(counted)}',
          subtitle: '',
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          showDivider: false,
          showTrailingArrow: true,
          onTap: () => _chooseSource(context, ref, sources, counted?.id),
        ),
        const Gap(Spacing.sm),
        const AppDivider(),
        const Gap(Spacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.savings_outlined),
            label: const Text('Set budget'),
            onPressed: () => _setTarget(context, ref),
          ),
        ),
      ],
    );
    final breakdown =
        chart == null
            ? Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
              child: Center(
                child: Text(
                  'Add at least two amounts to see a breakdown.',
                  style: TextStyle(color: scheme.outline),
                ),
              ),
            )
            : PlanningSpendChart(chart: chart);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(block.title ?? 'Budget', style: theme.textTheme.titleMedium),
        const Gap(Spacing.sm),
        _BudgetTabs(budget: progress, breakdown: breakdown),
      ],
    );
  }
}

/// Budget | Breakdown, switched in place (the plan scrolls, so no pager).
class _BudgetTabs extends StatefulWidget {
  const _BudgetTabs({required this.budget, required this.breakdown});
  final Widget budget;
  final Widget breakdown;

  @override
  State<_BudgetTabs> createState() => _BudgetTabsState();
}

class _BudgetTabsState extends State<_BudgetTabs>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SimpleTabs(
        controller: _tabs,
        scrollable: false,
        tabs: const [
          AppTabItem(label: 'Budget', icon: Icons.donut_large_rounded),
          AppTabItem(label: 'Breakdown', icon: Icons.pie_chart_outline_rounded),
        ],
      ),
      const Gap(Spacing.lg),
      _tabs.index == 0 ? widget.budget : widget.breakdown,
    ],
  );
}

class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({required this.currency, required this.initialMinor});
  final String currency;
  final int? initialMinor;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late final _c = TextEditingController(
    text:
        widget.initialMinor == null
            ? ''
            : formatPlanningMoney(
              widget.initialMinor!,
              widget.currency,
            ).replaceAll(RegExp(r'[^0-9.,]'), ''),
  );

  /// Set once Done is tapped with nothing usable, so the field says why.
  bool _tried = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Done saves; an empty or unreadable amount keeps the sheet open.
  void _done() {
    final parsed = parsePlanningMoney(_c.text, widget.currency);
    if (parsed == null) {
      setState(() => _tried = true);
      return;
    }
    popPlanningSheet(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parsePlanningMoney(_c.text, widget.currency);
    final error =
        (_c.text.isNotEmpty || _tried) && parsed == null
            ? 'Enter an amount like 500'
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BottomSheetHeader(title: 'Set budget', actionLabel: 'Save', onPressed: _done),
        AppTextFormField(
          controller: _c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          label: 'Budget',
          hintText: planningMoneyHint(widget.currency, 500),
          labelColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.6),
          suffixText: widget.currency,
          errorText: error,
          onChanged: (_) => setState(() {}),
          onFieldSubmitted: (_) => _done(),
        ),
      ],
    );
  }
}
