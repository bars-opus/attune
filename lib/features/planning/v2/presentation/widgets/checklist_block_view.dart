import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_v2_error.dart';
import '../../data/planning_v2_models.dart';
import '../../domain/code_point_limit.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';

class ChecklistBlockView extends ConsumerStatefulWidget {
  const ChecklistBlockView({super.key, required this.args, required this.block, required this.members});
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final List<PlanningMember> members;

  @override
  ConsumerState<ChecklistBlockView> createState() => _ChecklistBlockViewState();
}

class _ChecklistBlockViewState extends ConsumerState<ChecklistBlockView> {
  final _add = TextEditingController();
  final _addFocus = FocusNode();
  bool _showDone = false;

  PlanningEntryController get _ctl => ref.read(planningV2EntryProvider(widget.args).notifier);

  @override
  void dispose() {
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e);
    }
  }

  Future<void> _submit() async {
    final text = _add.text.trim();
    if (text.isEmpty) return;
    _add.clear();
    _addFocus.requestFocus();
    await _guard(() => _ctl.addItem(widget.block.id, text));
  }

  Future<void> _delete(PlanningItem item) async {
    final index = widget.block.items.indexOf(item);
    await _guard(() => _ctl.deleteItem(widget.block.id, item.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Removed ${item.text}'),
      action: SnackBarAction(
          label: 'Undo', onPressed: () => _guard(() => _ctl.restoreItem(widget.block.id, item.id, index: index))),
    ));
  }

  Future<void> _edit(PlanningItem item) async {
    final result = await showModalBottomSheet<({String text, String? section, String? assignedTo, DateTime? dueDate})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemEditor(item: item, members: widget.members),
    );
    if (result == null) return;
    try {
      await _ctl.updateItem(widget.block.id, item,
          text: result.text, section: result.section, assignedTo: result.assignedTo, dueDate: result.dueDate);
    } on PlanningV2StaleVersion {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Your partner just changed this item. Showing theirs.')));
      }
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e);
    }
  }

  Widget _row(PlanningItem item) {
    final assignee = widget.members.where((m) => m.id == item.assignedTo).firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('item-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: Spacing.horizontalMd,
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => _delete(item),
      child: Row(children: [
        Semantics(
          container: true,
          label: '${item.text}, ${item.isChecked ? 'done' : 'not done'}',
          excludeSemantics: true,
          checked: item.isChecked,
          child: Checkbox(
            value: item.isChecked,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onChanged: (v) => _guard(() => _ctl.setChecked(widget.block.id, item, v ?? false)),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _edit(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.smMd),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  item.text,
                  style: item.isChecked
                      ? TextStyle(decoration: TextDecoration.lineThrough, color: scheme.outline)
                      : null,
                ),
                if (item.dueDate != null)
                  Text('Due ${formatPlanningRange(item.dueDate, null)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline)),
              ]),
            ),
          ),
        ),
        if (assignee != null)
          Semantics(
            container: true,
            label: 'Assigned to ${assignee.displayName}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: CircleAvatar(radius: 12, child: Text(assignee.initial, style: const TextStyle(fontSize: 12))),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = [for (final i in widget.block.items) if (!i.isChecked) i];
    final done = [for (final i in widget.block.items) if (i.isChecked) i];
    final rows = <Widget>[];
    String? section;
    for (final item in open) {
      if (item.section != null && item.section != section) {
        rows.add(Padding(
          padding: const EdgeInsets.only(top: Spacing.sm, left: Spacing.xs),
          child: Text(item.section!, style: Theme.of(context).textTheme.labelLarge),
        ));
      }
      section = item.section;
      rows.add(_row(item));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.block.title ?? 'Checklist', style: Theme.of(context).textTheme.titleMedium),
      ...rows,
      TextField(
        controller: _add,
        focusNode: _addFocus,
        inputFormatters: [CodePointLengthFormatter(500)],
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          hintText: 'Add item', prefixIcon: Icon(Icons.add_rounded), counterText: '', border: InputBorder.none),
        onSubmitted: (_) => _submit(),
      ),
      if (done.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: Icon(_showDone ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: Text('${done.length} done'),
            onPressed: () => setState(() => _showDone = !_showDone),
          ),
        ),
      if (_showDone) ...[for (final i in done) _row(i)],
    ]);
  }
}

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({required this.item, required this.members});
  final PlanningItem item;
  final List<PlanningMember> members;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final _text = TextEditingController(text: widget.item.text);
  late final _section = TextEditingController(text: widget.item.section ?? '');
  late String? _assignee = widget.item.assignedTo;
  late DateTime? _due = widget.item.dueDate;

  @override
  void dispose() {
    _text.dispose();
    _section.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
            left: Spacing.lg, right: Spacing.lg, bottom: MediaQuery.viewInsetsOf(context).bottom + Spacing.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _text,
            inputFormatters: [CodePointLengthFormatter(500)],
            buildCounter: codePointCounter(_text, 500),
            decoration: const InputDecoration(labelText: 'Item'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _section,
            inputFormatters: [CodePointLengthFormatter(40)],
            buildCounter: codePointCounter(_section, 40),
            decoration: const InputDecoration(labelText: 'Section (optional)'),
          ),
          const SizedBox(height: Spacing.sm),
          Text("Who's on it", style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Spacing.xs),
          SegmentedButton<String>(
            segments: [
              for (final m in widget.members) ButtonSegment(value: m.id, label: Text(m.displayName)),
              const ButtonSegment(value: '', label: Text('Either')),
            ],
            selected: {_assignee ?? ''},
            onSelectionChanged: (s) => setState(() => _assignee = s.first.isEmpty ? null : s.first),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            leading: const Icon(Icons.event_rounded),
            title: Text(_due == null ? 'No due date' : 'Due ${formatPlanningRange(_due, null)}'),
            trailing: _due == null
                ? null
                : IconButton(
                    tooltip: 'Clear due date',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _due = null),
                  ),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                  context: context, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10),
                  initialDate: _due ?? now);
              if (d != null) setState(() => _due = d);
            },
          ),
          const SizedBox(height: Spacing.lg),
          AppButton(
            label: 'Save',
            isDisabled: _text.text.trim().isEmpty,
            onPressed: () => Navigator.of(context).pop((
              text: _text.text.trim(),
              section: _section.text.trim().isEmpty ? null : _section.text.trim(),
              assignedTo: _assignee,
              dueDate: _due,
            )),
          ),
        ]),
      );
}
