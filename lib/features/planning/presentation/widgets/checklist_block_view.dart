import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:attune/core/ui/motion/animated_keyed_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../../domain/code_point_limit.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

class ChecklistBlockView extends ConsumerStatefulWidget {
  const ChecklistBlockView({
    super.key,
    required this.args,
    required this.block,
    required this.members,
    this.menu,
  });
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final List<PlanningMember> members;

  /// The block's options menu, shown at the end of the heading row so the
  /// items below get the full width.
  final Widget? menu;

  @override
  ConsumerState<ChecklistBlockView> createState() => _ChecklistBlockViewState();
}

class _ChecklistBlockViewState extends ConsumerState<ChecklistBlockView> {
  final _add = TextEditingController();
  final _addFocus = FocusNode();
  bool _showDone = false;

  PlanningEntryController get _ctl =>
      ref.read(planningEntryProvider(widget.args).notifier);

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
      if (mounted) showPlanningError(context, e);
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
    context.showInfoSnackbar(
      'Removed ${item.text}',
      actionLabel: 'Undo',
      onAction:
          () => _guard(
            () => _ctl.restoreItem(widget.block.id, item.id, index: index),
          ),
    );
  }

  Future<void> _edit(PlanningItem item) async {
    final result = await showModalBottomSheet<
      ({String text, String? section, String? assignedTo, DateTime? dueDate})
    >(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.neutral,
      builder: (_) => _ItemEditor(item: item, members: widget.members),
    );
    if (result == null) return;
    try {
      await _ctl.updateItem(
        widget.block.id,
        item,
        text: result.text,
        section: result.section,
        assignedTo: result.assignedTo,
        dueDate: result.dueDate,
      );
    } on PlanningStaleVersion {
      if (mounted) {
        context.showInfoSnackbar(
          'Your partner just changed this item. Showing theirs.',
        );
      }
    } catch (e) {
      if (mounted) showPlanningError(context, e);
    }
  }

  Widget _row(PlanningItem item) {
    final assignee =
        widget.members.where((m) => m.id == item.assignedTo).firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('item-${item.id}'),
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
        await _delete(item);
        return false;
      },
      child: Row(
        children: [
          Semantics(
            container: true,
            label: '${item.text}, ${item.isChecked ? 'done' : 'not done'}',
            excludeSemantics: true,
            checked: item.isChecked,
            child: Checkbox(
              value: item.isChecked,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onChanged:
                  (v) => _guard(
                    () => _ctl.setChecked(widget.block.id, item, v ?? false),
                  ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _edit(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.smMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.text,
                      style:
                          item.isChecked
                              ? TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: scheme.outline,
                              )
                              : null,
                    ),
                    if (item.dueDate != null)
                      Text(
                        'Due ${formatPlanningRange(item.dueDate, null)}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: scheme.primary),
                      ),
                  ],
                ),
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
                child: CircleAvatar(
                  radius: 12,
                  child: Text(
                    assignee.initial,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = [
      for (final i in widget.block.items)
        if (!i.isChecked) i,
    ];
    final done = [
      for (final i in widget.block.items)
        if (i.isChecked) i,
    ];
    final rows = <Widget>[];
    String? section;
    for (final item in open) {
      if (item.section != null && item.section != section) {
        rows.add(
          Padding(
            key: ValueKey('section-${item.id}'), // keyed by its first item, for the list's motion
            padding: const EdgeInsets.only(top: Spacing.sm, left: Spacing.xs),
            child: Text(
              item.section!,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        );
      }
      section = item.section;
      rows.add(_row(item));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Block headings share one look: the Date block's (smaller, not bold).
        Row(
          children: [
            Expanded(
              child: Text(
                widget.block.title ?? 'Checklist',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w400),
              ),
            ),
            if (widget.menu != null) widget.menu!,
          ],
        ),
        const Gap(Spacing.md),
        // Items grow in, fold away when ticked or deleted, and glide back on Undo.
        AnimatedKeyedColumn(children: rows),
        const Gap(Spacing.md),
        TextField(
          controller: _add,
          focusNode: _addFocus,
          inputFormatters: [CodePointLengthFormatter(500)],
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Add item',
            prefixIcon: Icon(Icons.add_rounded),
            counterText: '',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (done.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: Icon(
                _showDone
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text('${done.length} done'),
              onPressed: () => setState(() => _showDone = !_showDone),
            ),
          ),
        // Always there, so opening it lets the done items grow in.
        AnimatedKeyedColumn(children: [if (_showDone) for (final i in done) _row(i)]),
      ],
    );
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

  /// Set once Done is tapped with the item emptied, so its field says so.
  bool _tried = false;

  @override
  void dispose() {
    _text.dispose();
    _section.dispose();
    super.dispose();
  }

  void _done() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _tried = true);
      return;
    }
    final section = _section.text.trim();
    popPlanningSheet(context, (
      text: text,
      section: section.isEmpty ? null : section,
      assignedTo: _assignee,
      dueDate: _due,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    // A tap on any blank part of the sheet puts the keyboard away.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // No title; Done saves. Stays put while the fields scroll.
            BottomSheetHeader(title: '', onPressed: _done),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  0,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextFormField(
                      controller: _text,
                      label: 'Item',
                      labelColor: labelColor,
                      errorText:
                          _tried && _text.text.trim().isEmpty
                              ? 'Type the item'
                              : null,
                      inputFormatters: [CodePointLengthFormatter(500)],
                      buildCounter: codePointCounter(_text, 500),
                      onChanged: (_) => setState(() {}),
                    ),
                    AppTextFormField(
                      controller: _section,
                      label: 'Section (optional)',
                      labelColor: labelColor,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [CodePointLengthFormatter(40)],
                      buildCounter: codePointCounter(_section, 40),
                    ),
                    const Gap(Spacing.sm),
                    Text(
                      "Who's on it",
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const Gap(Spacing.xs),
                    SegmentedButton<String>(
                      segments: [
                        for (final m in widget.members)
                          ButtonSegment(
                            value: m.id,
                            label: Text(m.displayName),
                          ),
                        const ButtonSegment(value: '', label: Text('Either')),
                      ],
                      selected: {_assignee ?? ''},
                      onSelectionChanged:
                          (s) => setState(
                            () => _assignee = s.first.isEmpty ? null : s.first,
                          ),
                    ),
                    // The same row the Date block picks its dates from.
                    InfoRowWidget(
                      icon: Icons.event_rounded,
                      showAvatar: false,
                      iconSize: 20.h,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title:
                          _due == null
                              ? 'No due date'
                              : 'Due ${formatPlanningRange(_due, null)}',
                      subtitle: '',
                      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                      showDivider: false,
                      showTrailingArrow: _due == null,
                      trailing:
                          _due == null
                              ? null
                              : IconButton(
                                tooltip: 'Clear due date',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => setState(() => _due = null),
                              ),
                      onTap: () async {
                        final d = await pickPlanningDate(
                          context,
                          initial: _due,
                          onChanged: (d) => setState(() => _due = d),
                        );
                        if (mounted) setState(() => _due = d);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
