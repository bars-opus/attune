import 'package:attune/core/widgets/dismiss_keyboard_on_tap.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/core/ui/motion/animated_keyed_column.dart';
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
String nextPlanningColumnKey(
  List<PlanningTableColumn> columns,
  List<PlanningItem> rows,
) {
  var max = -1;
  for (final k in [
    for (final c in columns) c.key,
    for (final r in rows) ...r.cells.keys,
  ]) {
    final n = int.tryParse(k.startsWith('c') ? k.substring(1) : '');
    if (n != null && n > max) max = n;
  }
  return 'c${max + 1}';
}

/// [v] as the column's type, or null when it doesn't fit (a column whose
/// type changed while a partner still had the old value on screen).
Object? _typed(PlanningColumnType type, Object? v) => switch (type) {
  PlanningColumnType.money || PlanningColumnType.number => v is num ? v : null,
  PlanningColumnType.date =>
    v is String && DateTime.tryParse(v) != null ? v : null,
  PlanningColumnType.check => v is bool ? v : null,
  PlanningColumnType.text => v is String ? v : null,
};

/// A small typed table: up to 12 columns, 50 rows. A row opens an editor
/// with one field per column; money cells use the plan's currency.
class TableBlockView extends ConsumerWidget {
  const TableBlockView({
    super.key,
    required this.args,
    required this.block,
    required this.currency,
    this.menu,
  });
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final String currency;

  /// The block's options menu, shown at the end of the heading row so the
  /// grid below gets the full width.
  final Widget? menu;

  Future<void> _editRow(
    BuildContext context,
    WidgetRef ref,
    PlanningItem? row,
  ) async {
    final cells = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      // Keyboard up, the sheet scrolls inside this cap instead of growing
      // over the status bar.
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.neutral,
      builder:
          (_) => DismissKeyboardOnTap(
            child: _RowEditor(
              // Numbered as the grid shows it; a new row is the next one.
              title:
                  'Row ${(row == null ? block.items.length : block.items.indexOf(row)) + 1}',
              columns: block.columns,
              cells: row?.cells ?? const {},
              currency: currency,
            ),
          ),
    );
    if (cells == null || !context.mounted) return;
    try {
      await ref
          .read(planningEntryProvider(args).notifier)
          .saveRichItem(block.id, existing: row, fields: {'cells': cells});
    } on PlanningStaleVersion {
      if (context.mounted) {
        context.showInfoSnackbar(
          'Your partner just changed this row. Showing theirs.',
        );
      }
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<void> _editColumns(BuildContext context, WidgetRef ref) async {
    final columns = await showModalBottomSheet<List<PlanningTableColumn>>(
      context: context,
      isScrollControlled: true,
      // Keyboard up, the sheet scrolls inside this cap instead of growing
      // over the status bar.
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.neutral,
      builder:
          (_) => DismissKeyboardOnTap(
            child: _ColumnsEditor(columns: block.columns, rows: block.items),
          ),
    );
    if (columns == null || !context.mounted) return;
    try {
      await ref.read(planningEntryProvider(args).notifier).updateBlockPayload(
        block,
        {
          if (block.title != null) 'title': block.title,
          'columns': [for (final c in columns) c.toJson()],
        },
      );
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlanningItem row,
  ) async {
    final ctl = ref.read(planningEntryProvider(args).notifier);
    final index = block.items.indexOf(row);
    try {
      await ctl.deleteItem(block.id, row.id);
    } catch (e) {
      if (context.mounted) showPlanningError(context, e);
      return;
    }
    if (!context.mounted) return;
    context.showInfoSnackbar(
      'Row removed',
      actionLabel: 'Undo',
      onAction: () => ctl.restoreItem(block.id, row.id, index: index),
    );
  }

  Widget _cell(BuildContext context, PlanningTableColumn col, Object? raw) {
    final scheme = Theme.of(context).colorScheme;
    if (raw == null) return Text('–', style: TextStyle(color: scheme.outline));
    final v = _typed(col.type, raw);
    if (v == null)
      return Text('$raw', maxLines: 2, overflow: TextOverflow.ellipsis);
    return switch (col.type) {
      PlanningColumnType.check => Icon(
        v == true
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        size: 20,
        color: v == true ? scheme.primary : scheme.outline,
        semanticLabel: v == true ? 'Yes' : 'No',
      ),
      PlanningColumnType.money => Text(
        formatPlanningMoney((v as num).toInt(), currency),
      ),
      PlanningColumnType.date => Text(
        DateFormat.MMMd().format(DateTime.parse(v as String)),
      ),
      PlanningColumnType.number => Text(
        NumberFormat.decimalPattern().format(v as num),
      ),
      PlanningColumnType.text => Text(
        '$v',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    };
  }

  /// A bordered grid: an outer rounded border, a line between every column
  /// and row, and a shaded header. Columns share the width when they fit and
  /// scroll sideways when they don't.
  Widget _grid(BuildContext context, WidgetRef ref, double maxWidth) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final columns = block.columns;
    final line = BorderSide(color: scheme.outlineVariant);
    final width = (maxWidth / columns.length).clamp(120.0, double.infinity);

    Widget cell(int i, EdgeInsets padding, Widget child) => Container(
      key: ValueKey('planning-table-cell-${columns[i].key}'),
      width: width,
      padding: padding,
      alignment: Alignment.centerLeft,
      decoration:
          i < columns.length - 1
              ? BoxDecoration(border: Border(right: line))
              : null,
      child: child,
    );

    Widget cells(double minHeight, List<Widget> children) => IntrinsicHeight(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        key: const ValueKey('planning-table-grid'),
        // The outline is painted over the cells and the cells are clipped to
        // the same rounded rect, so the shaded header can't cover its corners.
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(borderRadius: BorderRadiusTokens.smAll),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadiusTokens.smAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const ValueKey('planning-table-header'),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
              child: cells(0, [
                for (final (i, c) in columns.indexed)
                  cell(
                    i,
                    const EdgeInsets.symmetric(
                      vertical: Spacing.xs,
                      horizontal: Spacing.sm,
                    ),
                    Text(
                      c.label,
                      style: theme.textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ]),
            ),
            // Rows grow in, fold away when deleted, and glide back on Undo. Start-
            // aligned: the grid scrolls sideways, so it has no width to stretch to.
            AnimatedKeyedColumn(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in block.items)
                  Dismissible(
                    key: ValueKey('row-${row.id}'),
                    direction:
                        DismissDirection
                            .startToEnd, // swipe right = delete, as everywhere in Planning
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: Spacing.horizontalMd,
                      color: scheme.errorContainer,
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    // The delete takes the row away itself (and puts it back if it fails),
                    // so the swipe never leaves a dismissed widget in the tree.
                    confirmDismiss: (_) async {
                      await _delete(context, ref, row);
                      return false;
                    },
                    child: InkWell(
                      onTap: () => _editRow(context, ref, row),
                      child: Container(
                        key: const ValueKey('planning-table-row'),
                        decoration: BoxDecoration(border: Border(top: line)),
                        child: cells(48, [
                          for (final (i, c) in columns.indexed)
                            cell(
                              i,
                              const EdgeInsets.symmetric(
                                vertical: Spacing.sm,
                                horizontal: Spacing.sm,
                              ),
                              _cell(context, c, row.cells[c.key]),
                            ),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final columns = block.columns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                block.title ?? 'Table',
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Edit columns',
              icon: const Icon(Icons.view_column_outlined),
              onPressed: () => _editColumns(context, ref),
            ),
            if (menu != null) menu!,
          ],
        ),
        if (columns.isNotEmpty)
          LayoutBuilder(
            builder:
                (context, constraints) =>
                    _grid(context, ref, constraints.maxWidth),
          ),
        if (block.items.length < 50)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add row'),
              onPressed:
                  columns.isEmpty ? null : () => _editRow(context, ref, null),
            ),
          ),
      ],
    );
  }
}

class _RowEditor extends StatefulWidget {
  const _RowEditor({
    required this.title,
    required this.columns,
    required this.cells,
    required this.currency,
  });
  final String title;
  final List<PlanningTableColumn> columns;
  final Map<String, dynamic> cells;
  final String currency;

  @override
  State<_RowEditor> createState() => _RowEditorState();
}

class _RowEditorState extends State<_RowEditor> {
  late final Map<String, dynamic> _values = {
    for (final c in widget.columns)
      if (_typed(c.type, widget.cells[c.key]) != null)
        c.key: widget.cells[c.key],
  };
  late final Map<String, TextEditingController> _text = {
    for (final c in widget.columns)
      if (c.type == PlanningColumnType.text ||
          c.type == PlanningColumnType.number ||
          c.type == PlanningColumnType.money)
        c.key: TextEditingController(text: _initial(c)),
  };

  String _initial(PlanningTableColumn c) {
    final v = _typed(c.type, widget.cells[c.key]);
    if (v == null) return '';
    if (c.type == PlanningColumnType.money) {
      return formatPlanningMoney(
        (v as num).toInt(),
        widget.currency,
      ).replaceAll(RegExp(r'[^0-9.,]'), '');
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

  /// Why a typed number or amount can't be saved, shown under its field.
  String? _error(PlanningTableColumn c) {
    final t = _text[c.key]?.text.trim() ?? '';
    if (t.isEmpty) return null;
    return switch (c.type) {
      PlanningColumnType.number =>
        num.tryParse(t.replaceAll(',', '')) == null ? 'Enter a number' : null,
      PlanningColumnType.money =>
        parsePlanningMoney(t, widget.currency) == null
            ? 'Enter an amount like 500'
            : null,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stays put while the fields scroll. Done saves; an unreadable entry
          // keeps the sheet open and its field says why.
          BottomSheetHeader(
            title: widget.title,
            onPressed: () {
              final collected = _collect();
              if (collected != null) popPlanningSheet(context, collected);
            },
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                0,
                Spacing.md,
                Spacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, c) in widget.columns.indexed) ...[
                    if (i > 0) const Gap(Spacing.sm),
                    switch (c.type) {
                      PlanningColumnType.text => AppTextFormField(
                        controller: _text[c.key],
                        label: c.label,
                        labelPadding: const EdgeInsets.only(left: Spacing.lg),
                        labelColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                        height: FormTokens.compactFieldHeight,
                        inputFormatters: [CodePointLengthFormatter(200)],
                        onChanged: (_) => setState(() {}),
                      ),
                      PlanningColumnType.number ||
                      PlanningColumnType.money => AppTextFormField(
                        controller: _text[c.key],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.,-]'),
                          ),
                        ],
                        label: c.label,
                        labelPadding: const EdgeInsets.only(left: Spacing.lg),
                        labelColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                        // Room for an error line only while there is one.
                        height:
                            _error(c) == null
                                ? FormTokens.compactFieldHeight
                                : null,
                        errorText: _error(c),
                        suffixText:
                            c.type == PlanningColumnType.money
                                ? widget.currency
                                : null,
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
                        subtitle: Text(
                          _values[c.key] == null
                              ? 'No date'
                              : DateFormat.yMMMd().format(
                                DateTime.parse(_values[c.key] as String),
                              ),
                        ),
                        trailing: const Icon(Icons.event_rounded),
                        onTap: () async {
                          final d = await pickPlanningDate(
                            context,
                            initial:
                                _values[c.key] == null
                                    ? null
                                    : DateTime.parse(_values[c.key] as String),
                            onChanged:
                                (d) => setState(
                                  () => _values[c.key] = planningYmd(d),
                                ),
                          );
                          if (mounted)
                            setState(() => _values[c.key] = planningYmd(d));
                        },
                      ),
                    },
                  ],
                ],
              ),
            ),
          ),
        ],
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
    for (final c in widget.columns)
      (c.key, TextEditingController(text: c.label), c.type),
  ];

  @override
  void dispose() {
    for (final c in _cols) {
      c.$2.dispose();
    }
    super.dispose();
  }

  String _nextKey() => nextPlanningColumnKey([
    for (final c in _cols)
      PlanningTableColumn(key: c.$1, label: '', type: c.$3),
    ...widget.columns,
  ], widget.rows);

  static const _typeLabels = {
    PlanningColumnType.text: 'Text',
    PlanningColumnType.number: 'Number',
    PlanningColumnType.money: 'Money',
    PlanningColumnType.date: 'Date',
    PlanningColumnType.check: 'Yes / no',
  };

  /// Set once Done is tapped with a column unnamed, so its field says so.
  bool _tried = false;

  void _done() {
    if (_cols.isEmpty || _cols.any((c) => c.$2.text.trim().isEmpty)) {
      setState(() => _tried = true);
      return;
    }
    popPlanningSheet(context, [
      for (final c in _cols)
        PlanningTableColumn(key: c.$1, label: c.$2.text.trim(), type: c.$3),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stays put while the columns scroll. Done saves.
          // No title: each field is already labelled Column 1, Column 2…
          BottomSheetHeader(title: '', onPressed: _done),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                0,
                Spacing.md,
                Spacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _cols.length; i++)
                    AppTextFormField(
                      controller: _cols[i].$2,
                      label: 'Column ${i + 1}',
                      labelPadding: const EdgeInsets.only(left: Spacing.lg),
                      labelColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                      inputFormatters: [CodePointLengthFormatter(40)],
                      onChanged: (_) => setState(() {}),
                      // Exactly the box (the suffix holds it at 48), so the picker
                      // and remove button sit centred in it; taller while an error shows.
                      height: _unnamed(i) ? null : kMinInteractiveDimension,
                      errorText: _unnamed(i) ? 'Name this column' : null,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonHideUnderline(
                            child: DropdownButton<PlanningColumnType>(
                              value: _cols[i].$3,
                              items: [
                                for (final t in PlanningColumnType.values)
                                  DropdownMenuItem(
                                    value: t,
                                    child: Text(_typeLabels[t]!),
                                  ),
                              ],
                              onChanged:
                                  (t) => setState(
                                    () =>
                                        _cols[i] = (
                                          _cols[i].$1,
                                          _cols[i].$2,
                                          t ?? _cols[i].$3,
                                        ),
                                  ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove column',
                            icon: const Icon(Icons.close_rounded),
                            onPressed:
                                _cols.length == 1
                                    ? null
                                    : () => setState(
                                      () => _cols.removeAt(i).$2.dispose(),
                                    ),
                          ),
                        ],
                      ),
                    ),
                  if (_cols.length < _maxColumns)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add column'),
                        onPressed:
                            () => setState(
                              () => _cols.add((
                                _nextKey(),
                                TextEditingController(),
                                PlanningColumnType.text,
                              )),
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _unnamed(int i) => _tried && _cols[i].$2.text.trim().isEmpty;
}
