import 'package:attune/app/theme/design_tokens.dart';
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
  const BudgetBlockView({super.key, required this.args, required this.block, required this.defaultCurrency});
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final String defaultCurrency;

  String get _currency => block.targetCurrency ?? defaultCurrency;

  Future<void> _setTarget(BuildContext context, WidgetRef ref) async {
    final minor = await showDialog<int>(
      context: context,
      builder: (_) => _BudgetDialog(currency: _currency, initialMinor: block.targetMinor),
    );
    if (minor == null || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).setBudgetTarget(block, minor, _currency);
    } on PlanningStaleVersion {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Your partner just changed the budget. Showing theirs.')));
      }
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final computed = block.budget ?? const PlanningBudgetComputed(spentMinor: 0, otherCurrencies: []);
    final target = block.targetMinor;
    final spent = computed.spentMinor;
    final over = target != null && spent > target;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(block.title ?? 'Budget', style: theme.textTheme.titleMedium),
      const SizedBox(height: Spacing.sm),
      if (target == null)
        Text('No budget set. Spent so far: ${formatPlanningMoney(spent, _currency)}',
            style: TextStyle(color: scheme.outline))
      else ...[
        Semantics(
          label: '${formatPlanningMoney(spent, _currency)} spent of ${formatPlanningMoney(target, _currency)}',
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadiusTokens.smAll,
            child: LinearProgressIndicator(
              minHeight: 8,
              value: target == 0 ? 1 : (spent / target).clamp(0, 1).toDouble(),
              color: over ? scheme.error : scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Row(children: [
          Expanded(child: Text('${formatPlanningMoney(spent, _currency)} of ${formatPlanningMoney(target, _currency)}')),
          Text(
            over
                ? '${formatPlanningMoney(spent - target, _currency)} over budget'
                : '${formatPlanningMoney(target - spent, _currency)} left',
            style: theme.textTheme.titleSmall?.copyWith(color: over ? scheme.error : null),
          ),
        ]),
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
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.savings_outlined),
          label: const Text('Set budget'),
          onPressed: () => _setTarget(context, ref),
        ),
      ),
    ]);
  }
}

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.currency, required this.initialMinor});
  final String currency;
  final int? initialMinor;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final _c = TextEditingController(
      text: widget.initialMinor == null
          ? ''
          : formatPlanningMoney(widget.initialMinor!, widget.currency).replaceAll(RegExp(r'[^0-9.,]'), ''));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parsePlanningMoney(_c.text, widget.currency);
    return AlertDialog(
      title: const Text('Set budget'),
      content: TextField(
        controller: _c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(
          labelText: 'Budget',
          suffixText: widget.currency,
          errorText: _c.text.isNotEmpty && parsed == null ? 'Enter an amount like 500' : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: parsed == null ? null : () => Navigator.pop(context, parsePlanningMoney(_c.text, widget.currency)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
