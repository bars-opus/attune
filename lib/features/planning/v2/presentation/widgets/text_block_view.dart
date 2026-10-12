import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../data/planning_v2_models.dart';
import '../../domain/delta_sanitizer.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';
import '../screens/planning_v2_text_editor_screen.dart';
import 'planning_quill.dart';

/// Read-only render of a text block. Rebuilds its controller when the
/// block's version changes (partner edit or own save).
class TextBlockView extends StatefulWidget {
  const TextBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  @override
  State<TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends State<TextBlockView> {
  late QuillController _controller = _make();

  QuillController _make() => QuillController(
        document: Document.fromJson(sanitizeDelta(widget.block.delta).ops),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );

  @override
  void didUpdateWidget(TextBlockView old) {
    super.didUpdateWidget(old);
    if (old.block.version != widget.block.version || old.block.id != widget.block.id) {
      _controller.dispose();
      _controller = _make();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _edit() => Navigator.of(context).push(planningV2Route(
      PlanningV2TextEditorScreen(args: widget.args, block: widget.block)));

  @override
  Widget build(BuildContext context) {
    final empty = (widget.block.plainText ?? '').isEmpty;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: GestureDetector(
          onTap: _edit,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            child: empty
                ? Text('Tap to write', style: TextStyle(color: Theme.of(context).colorScheme.outline))
                : IgnorePointer(
                    child: planningQuillScope(
                      context,
                      QuillEditor.basic(controller: _controller, config: planningQuillEditorConfig(context)),
                    ),
                  ),
          ),
        ),
      ),
      IconButton(tooltip: 'Edit text', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
    ]);
  }
}
