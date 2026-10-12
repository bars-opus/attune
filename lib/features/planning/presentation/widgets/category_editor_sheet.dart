import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:flutter/material.dart';

import '../../domain/code_point_limit.dart';
import '../planning_ui.dart';

typedef CategoryDraft = ({String name, String icon, String color});

Future<CategoryDraft?> showCategoryEditorSheet(BuildContext context, {CategoryDraft? initial}) =>
    showModalBottomSheet<CategoryDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditor(initial: initial),
    );

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({this.initial});
  final CategoryDraft? initial;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name ?? '');
  late String _icon = widget.initial?.icon ?? 'star';
  late String _color = widget.initial?.color ?? 'teal';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg, right: Spacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.initial == null ? 'New category' : 'Edit category',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Spacing.md),
        TextField(
          controller: _name,
          autofocus: true,
          inputFormatters: [CodePointLengthFormatter(40)],
          buildCounter: codePointCounter(_name, 40),
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'Moving house'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Spacing.sm),
        Text('Icon', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Spacing.sm),
        Wrap(spacing: Spacing.xs, runSpacing: Spacing.xs, children: [
          for (final k in planningIconKeys)
            Semantics(
              container: true,
              label: 'Icon $k',
              selected: k == _icon,
              button: true,
              excludeSemantics: true,
              child: IconButton.filledTonal(
                isSelected: k == _icon,
                onPressed: () => setState(() => _icon = k),
                icon: Icon(planningIcon(k)),
              ),
            ),
        ]),
        const SizedBox(height: Spacing.md),
        Text('Colour', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Spacing.sm),
        Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
          for (final c in planningColorKeys)
            Semantics(
              container: true,
              label: 'Colour $c',
              selected: c == _color,
              button: true,
              excludeSemantics: true,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _color = c),
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: planningTone(context, c).container,
                      child: c == _color
                          ? Icon(Icons.check_rounded, color: planningTone(context, c).onContainer)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: Spacing.lg),
        AppButton(
          label: 'Save',
          isDisabled: !valid,
          onPressed: () => Navigator.of(context).pop((name: _name.text.trim(), icon: _icon, color: _color)),
        ),
      ]),
    );
  }
}
