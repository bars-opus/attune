import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../../domain/code_point_limit.dart';
import '../../domain/planning_money.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

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
          title: 'Add to it', label: 'Amount', action: 'Add', withNote: true,
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
      builder: (_) => _AmountDialog(title: 'Set the target', label: 'Target', action: 'Save', currency: currency),
    );
    if (fields == null || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).setTarget(block, fields['amount_minor'] as int, currency);
    } on PlanningStaleVersion {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Your partner just changed the target. Showing theirs.')));
      }
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Removed'),
      action: SnackBarAction(label: 'Undo', onPressed: () => ctl.restoreItem(block.id, item.id, index: index)),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = block.progress!;
    final summary = p.isChecklist
        ? (p.total == 0 ? 'Add steps to a checklist in this plan' : '${p.done} of ${p.total} done')
        : (p.target == null ? '${_amount(p, p.current)} so far' : '${_amount(p, p.current)} of ${_amount(p, p.target!)}');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(block.title ?? 'Progress', style: theme.textTheme.titleMedium),
      const SizedBox(height: Spacing.sm),
      Semantics(
        label: '$summary, ${(p.fraction * 100).round()} percent',
        excludeSemantics: true,
        child: ClipRRect(
          borderRadius: BorderRadiusTokens.smAll,
          child: LinearProgressIndicator(
            minHeight: 10,
            value: p.fraction,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ),
      const SizedBox(height: Spacing.xs),
      Row(children: [
        Expanded(child: Text(summary)),
        if (p.isComplete)
          Text('Reached 🎉', style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
      ]),
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
            onDismissed: (_) => _delete(context, ref, item),
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
  });
  final String title;
  final String label;
  final String action;
  final String? currency; // null = a whole-number count
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
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: widget.currency != null),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(widget.currency != null ? r'[0-9.,]' : r'[0-9]'))],
          decoration: InputDecoration(labelText: widget.label, suffixText: widget.currency),
          onChanged: (_) => setState(() {}),
        ),
        if (widget.withNote)
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
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
