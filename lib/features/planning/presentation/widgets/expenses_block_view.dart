import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../../domain/code_point_limit.dart';
import '../../domain/planning_money.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

/// Currencies offered first in the expense editor; the plan's own currency
/// is always included.
const planningCommonCurrencies = ['GHS', 'NGN', 'KES', 'ZAR', 'USD', 'EUR', 'GBP', 'CAD', 'AUD', 'JPY', 'IDR'];

/// Expense lines: what for, how much, who paid. Totals per currency; with
/// split on, each line can carry the other partner's share.
class ExpensesBlockView extends ConsumerWidget {
  const ExpensesBlockView({super.key, required this.args, required this.block, required this.detail});
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final PlanningEntryDetail detail;

  /// The sheet stays open until the save succeeds, and a new line keeps one
  /// id for the whole sheet, so a retry after a dropped response can't
  /// save the same money twice (checklist 2.18).
  Future<void> _edit(BuildContext context, WidgetRef ref, PlanningItem? item) async {
    final ctl = ref.read(planningEntryProvider(args).notifier);
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExpenseEditor(
        item: item,
        members: detail.members,
        me: ref.read(planningCurrentUserIdProvider),
        defaultCurrency: detail.entry.currency,
        splitOn: detail.entry.split != null,
        save: (fields, id) async {
          try {
            await ctl.saveRichItem(block.id, existing: item, id: id, fields: fields);
            return null;
          } on PlanningStaleVersion {
            messenger.showSnackBar(
                const SnackBar(content: Text('Your partner just changed this expense. Showing theirs.')));
            return null;
          } catch (e) {
            return planningErrorMessage(mapPlanningError(e));
          }
        },
      ),
    );
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
      content: Text('Removed ${item.text}'),
      action: SnackBarAction(label: 'Undo', onPressed: () => ctl.restoreItem(block.id, item.id, index: index)),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = <String, int>{};
    for (final i in block.items) {
      if (i.amountMinor != null && i.currency != null) totals[i.currency!] = (totals[i.currency!] ?? 0) + i.amountMinor!;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(block.title ?? 'Expenses', style: theme.textTheme.titleMedium),
      const SizedBox(height: Spacing.xs),
      if (block.items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Text('Nothing spent yet.', style: TextStyle(color: scheme.outline)),
        ),
      for (final item in block.items)
        Dismissible(
          key: ValueKey('expense-${item.id}'),
          direction: DismissDirection.startToEnd, // swipe right = delete, as everywhere in Planning
          background: Container(
            alignment: Alignment.centerLeft,
            padding: Spacing.horizontalMd,
            color: scheme.errorContainer,
            child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
          ),
          onDismissed: (_) => _delete(context, ref, item),
          child: InkWell(
            onTap: () => _edit(context, ref, item),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              child: Row(children: [
                Semantics(
                  label: 'Paid by ${planningMemberName(detail.members, item.paidBy)}',
                  excludeSemantics: true,
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: scheme.secondaryContainer,
                    child: Text(
                      detail.member(item.paidBy)?.initial ?? '?',
                      style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.smMd),
                Expanded(child: Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: Spacing.sm),
                if (item.amountMinor != null && item.currency != null)
                  Text(formatPlanningMoney(item.amountMinor!, item.currency!),
                      style: theme.textTheme.bodyLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ),
        ),
      if (totals.isNotEmpty) ...[
        const Divider(height: Spacing.md),
        Text(
          'Total ${totals.entries.map((e) => formatPlanningMoney(e.value, e.key)).join(' · ')}',
          style: theme.textTheme.titleSmall,
        ),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add expense'),
          onPressed: () => _edit(context, ref, null),
        ),
      ),
    ]);
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
  late final _amount = TextEditingController(text: _initialAmount(widget.item?.amountMinor));
  late final _share = TextEditingController(text: _initialAmount(widget.item?.splitShareMinor));
  late String _currency = widget.item?.currency ?? widget.defaultCurrency;
  late String? _paidBy = widget.item?.paidBy ?? widget.me;
  late bool _equal = widget.item?.splitShareMinor == null;
  late final String _id = widget.item?.id ?? const Uuid().v4();
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
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
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  String _initialAmount(int? minor) {
    if (minor == null) return '';
    final digits = planningCurrencyDigits(widget.item?.currency ?? widget.defaultCurrency);
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
  int? get _shareMinor => _equal ? null : parsePlanningMoney(_share.text, _currency);

  bool get _valid =>
      _label.text.trim().isNotEmpty &&
      _amountMinor != null &&
      (_equal || (_shareMinor != null && _shareMinor! <= _amountMinor!));

  @override
  Widget build(BuildContext context) {
    final currencies = {widget.defaultCurrency, _currency, ...planningCommonCurrencies}.toList();
    final amountError = _amount.text.isNotEmpty && _amountMinor == null ? 'Enter an amount like 12.50' : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, MediaQuery.viewInsetsOf(context).bottom + Spacing.md),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.item == null ? 'Add expense' : 'Edit expense', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _label,
            autofocus: widget.item == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What for'),
            inputFormatters: [CodePointLengthFormatter(120)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Spacing.smMd),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(labelText: 'Amount', errorText: amountError),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: Spacing.smMd),
            DropdownButton<String>(
              value: _currency,
              items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (c) => setState(() => _currency = c ?? _currency),
            ),
          ]),
          const SizedBox(height: Spacing.md),
          Text('Paid by', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Spacing.xs),
          Wrap(spacing: Spacing.sm, children: [
            for (final m in widget.members)
              ChoiceChip(
                label: Text(m.id == widget.me ? 'Me' : (m.displayName.isEmpty ? 'Partner' : m.displayName)),
                selected: _paidBy == m.id,
                onSelected: (_) => setState(() => _paidBy = m.id),
              ),
          ]),
          if (widget.splitOn) ...[
            const SizedBox(height: Spacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Split equally'),
              value: _equal,
              onChanged: (v) => setState(() => _equal = v),
            ),
            if (!_equal)
              TextField(
                controller: _share,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(
                    labelText: "The other person's share", helperText: 'What the one who did not pay owes'),
                onChanged: (_) => setState(() {}),
              ),
          ],
          const SizedBox(height: Spacing.md),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton(
            onPressed: _valid && !_saving ? _submit : null,
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ]),
      ),
    );
  }
}
