import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../../domain/code_point_limit.dart';
import '../../domain/planning_money.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

const _maxColumns = 12;

/// A key no column or row has used: rows can still hold values under a
/// removed column's key, and a new column must not inherit them.
String nextPlanningColumnKey(List<PlanningTableColumn> columns, List<PlanningItem> rows) {
  var max = -1;
  for (final k in [for (final c in columns) c.key, for (final r in rows) ...r.cells.keys]) {
    final n = int.tryParse(k.startsWith('c') ? k.substring(1) : '');
    if (n != null && n > max) max = n;
  }
  return 'c${max + 1}';
}

/// [v] as the column's type, or null when it doesn't fit (a column whose
/// type changed while a partner still had the old value on screen).
Object? _typed(PlanningColumnType type, Object? v) => switch (type) {
      PlanningColumnType.money || PlanningColumnType.number => v is num ? v : null,
      PlanningColumnType.date => v is String && DateTime.tryParse(v) != null ? v : null,
      PlanningColumnType.check => v is bool ? v : null,
      PlanningColumnType.text => v is String ? v : null,
    };

/// A small typed table: up to 12 columns, 50 rows. A row opens an editor
/// with one field per column; money cells use the plan's currency.
class TableBlockView extends ConsumerWidget {
  const TableBlockView({super.key, required this.args, required this.block, required this.currency});
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final String currency;

  Future<void> _editRow(BuildContext context, WidgetRef ref, PlanningItem? row) async {
    final cells = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RowEditor(columns: block.columns, cells: row?.cells ?? const {}, currency: currency),
    );
    if (cells == null || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).saveRichItem(block.id, existing: row, fields: {'cells': cells});
    } on PlanningStaleVersion {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Your partner just changed this row. Showing theirs.')));
      }
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<void> _editColumns(BuildContext context, WidgetRef ref) async {
    final columns = await showModalBottomSheet<List<PlanningTableColumn>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ColumnsEditor(columns: block.columns, rows: block.items),
    );
    if (columns == null || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).updateBlockPayload(block, {
        if (block.title != null) 'title': block.title,
        'columns': [for (final c in columns) c.toJson()],
      });
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, PlanningItem row) async {
    final ctl = ref.read(planningEntryProvider(args).notifier);
    final index = block.items.indexOf(row);
    try {
      await ctl.deleteItem(block.id, row.id);
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Row removed'),
      action: SnackBarAction(label: 'Undo', onPressed: () => ctl.restoreItem(block.id, row.id, index: index)),
    ));
  }

  Widget _cell(BuildContext context, PlanningTableColumn col, Object? raw) {
    final scheme = Theme.of(context).colorScheme;
    if (raw == null) return Text('–', style: TextStyle(color: scheme.outline));
    final v = _typed(col.type, raw);
    if (v == null) return Text('$raw', maxLines: 2, overflow: TextOverflow.ellipsis);
    return switch (col.type) {
      PlanningColumnType.check => Icon(
          v == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 20,
          color: v == true ? scheme.primary : scheme.outline,
          semanticLabel: v == true ? 'Yes' : 'No',
        ),
      PlanningColumnType.money => Text(formatPlanningMoney((v as num).toInt(), currency)),
      PlanningColumnType.date => Text(DateFormat.MMMd().format(DateTime.parse(v as String))),
      PlanningColumnType.number => Text(NumberFormat.decimalPattern().format(v as num)),
      PlanningColumnType.text => Text('$v', maxLines: 2, overflow: TextOverflow.ellipsis),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final columns = block.columns;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(block.title ?? 'Table', style: theme.textTheme.titleMedium)),
        IconButton(
            tooltip: 'Edit columns', icon: const Icon(Icons.view_column_outlined), onPressed: () => _editColumns(context, ref)),
      ]),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - Spacing.xxl * 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (final c in columns)
                SizedBox(
                  width: 120,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.xs, horizontal: Spacing.xs),
                    child: Text(c.label, style: theme.textTheme.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
            ]),
            Divider(height: 1, color: scheme.outlineVariant),
            for (final row in block.items)
              Dismissible(
                key: ValueKey('row-${row.id}'),
                direction: DismissDirection.startToEnd, // swipe right = delete, as everywhere in Planning
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: Spacing.horizontalMd,
                  color: scheme.errorContainer,
                  child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
                ),
                onDismissed: (_) => _delete(context, ref, row),
                child: InkWell(
                  onTap: () => _editRow(context, ref, row),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(children: [
                      for (final c in columns)
                        SizedBox(
                          width: 120,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: Spacing.sm, horizontal: Spacing.xs),
                            child: Align(alignment: Alignment.centerLeft, child: _cell(context, c, row.cells[c.key])),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
      if (block.items.length < 50)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add row'),
            onPressed: columns.isEmpty ? null : () => _editRow(context, ref, null),
          ),
        ),
    ]);
  }
}

class _RowEditor extends StatefulWidget {
  const _RowEditor({required this.columns, required this.cells, required this.currency});
  final List<PlanningTableColumn> columns;
  final Map<String, dynamic> cells;
  final String currency;

  @override
  State<_RowEditor> createState() => _RowEditorState();
}

class _RowEditorState extends State<_RowEditor> {
  late final Map<String, dynamic> _values = {
    for (final c in widget.columns)
      if (_typed(c.type, widget.cells[c.key]) != null) c.key: widget.cells[c.key],
  };
  late final Map<String, TextEditingController> _text = {
    for (final c in widget.columns)
      if (c.type == PlanningColumnType.text || c.type == PlanningColumnType.number || c.type == PlanningColumnType.money)
        c.key: TextEditingController(text: _initial(c)),
  };

  String _initial(PlanningTableColumn c) {
    final v = _typed(c.type, widget.cells[c.key]);
    if (v == null) return '';
    if (c.type == PlanningColumnType.money) {
      return formatPlanningMoney((v as num).toInt(), widget.currency).replaceAll(RegExp(r'[^0-9.,]'), '');
    }
    return '$v';
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Null when a field doesn't parse for its column type.
  Map<String, dynamic>? _collect() {
    final out = <String, dynamic>{};
    for (final c in widget.columns) {
      final t = _text[c.key]?.text.trim();
      switch (c.type) {
        case PlanningColumnType.text:
          out[c.key] = t!.isEmpty ? null : t;
        case PlanningColumnType.number:
          if (t!.isEmpty) {
            out[c.key] = null;
          } else {
            final n = num.tryParse(t.replaceAll(',', ''));
            if (n == null) return null;
            out[c.key] = n;
          }
        case PlanningColumnType.money:
          if (t!.isEmpty) {
            out[c.key] = null;
          } else {
            final m = parsePlanningMoney(t, widget.currency);
            if (m == null) return null;
            out[c.key] = m;
          }
        case PlanningColumnType.date || PlanningColumnType.check:
          out[c.key] = _values[c.key];
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final collected = _collect();
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, MediaQuery.viewInsetsOf(context).bottom + Spacing.md),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final c in widget.columns)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.smMd),
              child: switch (c.type) {
                PlanningColumnType.text => TextField(
                    controller: _text[c.key],
                    decoration: InputDecoration(labelText: c.label),
                    inputFormatters: [CodePointLengthFormatter(200)],
                    onChanged: (_) => setState(() {}),
                  ),
                PlanningColumnType.number || PlanningColumnType.money => TextField(
                    controller: _text[c.key],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
                    decoration: InputDecoration(
                        labelText: c.label, suffixText: c.type == PlanningColumnType.money ? widget.currency : null),
                    onChanged: (_) => setState(() {}),
                  ),
                PlanningColumnType.check => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.label),
                    value: _values[c.key] == true,
                    onChanged: (v) => setState(() => _values[c.key] = v),
                  ),
                PlanningColumnType.date => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.label),
                    subtitle: Text(_values[c.key] == null
                        ? 'No date'
                        : DateFormat.yMMMd().format(DateTime.parse(_values[c.key] as String))),
                    trailing: const Icon(Icons.event_rounded),
                    onTap: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                          context: context, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10),
                          initialDate: _values[c.key] == null ? now : DateTime.parse(_values[c.key] as String));
                      if (d != null) setState(() => _values[c.key] = planningYmd(d));
                    },
                  ),
              },
            ),
          FilledButton(
            onPressed: collected == null ? null : () => Navigator.pop(context, collected),
            child: const Text('Save'),
          ),
        ]),
      ),
    );
  }
}

class _ColumnsEditor extends StatefulWidget {
  const _ColumnsEditor({required this.columns, required this.rows});
  final List<PlanningTableColumn> columns;
  final List<PlanningItem> rows;

  @override
  State<_ColumnsEditor> createState() => _ColumnsEditorState();
}

class _ColumnsEditorState extends State<_ColumnsEditor> {
  late final List<(String, TextEditingController, PlanningColumnType)> _cols = [
    for (final c in widget.columns) (c.key, TextEditingController(text: c.label), c.type)
  ];

  @override
  void dispose() {
    for (final c in _cols) {
      c.$2.dispose();
    }
    super.dispose();
  }

  String _nextKey() => nextPlanningColumnKey(
      [for (final c in _cols) PlanningTableColumn(key: c.$1, label: '', type: c.$3), ...widget.columns], widget.rows);

  static const _typeLabels = {
    PlanningColumnType.text: 'Text',
    PlanningColumnType.number: 'Number',
    PlanningColumnType.money: 'Money',
    PlanningColumnType.date: 'Date',
    PlanningColumnType.check: 'Yes / no',
  };

  @override
  Widget build(BuildContext context) {
    final valid = _cols.isNotEmpty && _cols.every((c) => c.$2.text.trim().isNotEmpty);
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, MediaQuery.viewInsetsOf(context).bottom + Spacing.md),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Columns', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Spacing.sm),
          for (var i = 0; i < _cols.length; i++)
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cols[i].$2,
                  decoration: InputDecoration(labelText: 'Column ${i + 1}'),
                  inputFormatters: [CodePointLengthFormatter(40)],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              DropdownButton<PlanningColumnType>(
                value: _cols[i].$3,
                items: [
                  for (final t in PlanningColumnType.values) DropdownMenuItem(value: t, child: Text(_typeLabels[t]!))
                ],
                onChanged: (t) => setState(() => _cols[i] = (_cols[i].$1, _cols[i].$2, t ?? _cols[i].$3)),
              ),
              IconButton(
                tooltip: 'Remove column',
                icon: const Icon(Icons.close_rounded),
                onPressed: _cols.length == 1 ? null : () => setState(() => _cols.removeAt(i).$2.dispose()),
              ),
            ]),
          if (_cols.length < _maxColumns)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add column'),
                onPressed: () => setState(() => _cols.add((_nextKey(), TextEditingController(), PlanningColumnType.text))),
              ),
            ),
          const SizedBox(height: Spacing.sm),
          FilledButton(
            onPressed: valid
                ? () => Navigator.pop(context, [
                      for (final c in _cols) PlanningTableColumn(key: c.$1, label: c.$2.text.trim(), type: c.$3)
                    ])
                : null,
            child: const Text('Save'),
          ),
        ]),
      ),
    );
  }
}
