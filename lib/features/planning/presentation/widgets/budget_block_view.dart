import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/charts/arc_gauge.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../../domain/planning_money.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

/// A target against what this plan's expense lines add up to. Spent is
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final computed =
        block.budget ??
        const PlanningBudgetComputed(spentMinor: 0, otherCurrencies: []);
    final target = block.targetMinor;
    final spent = computed.spentMinor;
    final over = target != null && spent > target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(block.title ?? 'Budget', style: theme.textTheme.titleMedium),
        const Gap(Spacing.lg),
        if (target == null)
          Text(
            'No budget set. Spent so far: ${formatPlanningMoney(spent, _currency)}',
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
              caption: 'of ${formatPlanningMoney(target, _currency)}',
              semanticLabel: 'Budget',
            ),
          ),
          Center(
            child: Text(
              '${formatPlanningMoney(spent, _currency)} spent',
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
        const Gap(Spacing.xl),
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
  }
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
