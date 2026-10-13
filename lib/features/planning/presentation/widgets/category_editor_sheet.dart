import 'package:attune/core/widgets/dismiss_keyboard_on_tap.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:gap/gap.dart';
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
      builder: (_) => DismissKeyboardOnTap(child: _CategoryEditor(initial: initial)),
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
        const Gap(Spacing.md),
        AppTextFormField(
          controller: _name,
          autofocus: true,
          label: 'Name',
          hintText: 'Moving house',
          textInputAction: TextInputAction.done,
          inputFormatters: [CodePointLengthFormatter(40)],
          buildCounter: codePointCounter(_name, 40),
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
        ),
        const Gap(Spacing.sm),
        Text('Icon', style: Theme.of(context).textTheme.labelLarge),
        const Gap(Spacing.sm),
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
                // The chosen icon previews the category row: its colour's
                // fill with a background-coloured icon.
                style: k == _icon
                    ? IconButton.styleFrom(
                        backgroundColor: planningCategoryFill(context, _color),
                        foregroundColor: Theme.of(context).colorScheme.background, // ignore: deprecated_member_use
                      )
                    : null,
                onPressed: () => setState(() => _icon = k),
                icon: Icon(planningIcon(k)),
              ),
            ),
        ]),
        const Gap(Spacing.md),
        Text('Colour', style: Theme.of(context).textTheme.labelLarge),
        const Gap(Spacing.sm),
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
                      backgroundColor: planningCategoryFill(context, c),
                      child: c == _color
                          ? Icon(Icons.check_rounded,
                              color: Theme.of(context).colorScheme.background) // ignore: deprecated_member_use
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ]),
        const Gap(Spacing.lg),
        AppButton(
          label: 'Save',
          isDisabled: !valid,
          onPressed: () => Navigator.of(context).pop((name: _name.text.trim(), icon: _icon, color: _color)),
        ),
      ]),
    );
  }
}
