// Spec 2 W3b (§3.2 D3, §3.15 D3): a searchable, labelled picker sheet.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

Future<T?> showDatingPicker<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> items,
  T? selected,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder:
      (sheet) => AllowLargeText(
        child: _Picker<T>(title: title, items: items, selected: selected),
      ),
);

class _Picker<T> extends StatefulWidget {
  const _Picker({required this.title, required this.items, this.selected});

  final String title;
  final List<(T, String)> items;
  final T? selected;

  @override
  State<_Picker<T>> createState() => _PickerState<T>();
}

class _PickerState<T> extends State<_Picker<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final shown = [
      for (final item in widget.items)
        if (item.$2.toLowerCase().contains(_query.toLowerCase())) item,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Semantics(
                header: true,
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            if (widget.items.length > 6)
              Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: TextField(
                  // Final fix (M-12): a faith or a place searched for is not
                  // learnt by the keyboard either.
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  decoration: InputDecoration(labelText: loc.dating_search),
                  onChanged: (q) => setState(() => _query = q),
                ),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final (value, label) in shown)
                    ListTile(
                      title: Text(label),
                      selected: value == widget.selected,
                      trailing:
                          value == widget.selected
                              ? const Icon(Icons.check)
                              : null,
                      onTap: () => Navigator.of(context).pop(value),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
