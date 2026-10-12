import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attune/app/theme/design_tokens.dart';

import '../../data/planning_v2_models.dart';
import '../../domain/delta_sanitizer.dart';
import '../../domain/planning_v2_limits.dart';
import '../planning_v2_providers.dart';
import '../planning_v2_ui.dart';
import '../widgets/conflict_sheet.dart';
import '../widgets/planning_quill.dart';

class PlanningV2TextEditorScreen extends ConsumerStatefulWidget {
  const PlanningV2TextEditorScreen({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  @override
  ConsumerState<PlanningV2TextEditorScreen> createState() => PlanningV2TextEditorScreenState();
}

class PlanningV2TextEditorScreenState extends ConsumerState<PlanningV2TextEditorScreen> {
  static const tokens = ['yellow', 'green', 'blue', 'pink', 'purple'];

  late QuillController _controller = _load(widget.block.delta);
  late int _baseVersion = widget.block.version;
  StreamSubscription<DocChange>? _changes;
  bool _dirty = false;
  bool _saving = false;

  @visibleForTesting
  QuillController get controller => _controller;

  QuillController _load(List<Map<String, dynamic>> ops) {
    _changes?.cancel();
    final c = QuillController(
      document: Document.fromJson(sanitizeDelta(ops).ops),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _changes = c.document.changes.listen((_) {
      if (!_dirty && mounted) setState(() => _dirty = true);
    });
    return c;
  }

  @override
  void dispose() {
    _changes?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    final clean = sanitizeDelta(_controller.document.toDelta().toJson());
    if (deltaPlainText(clean.ops).runes.length > PlanningV2Limits.textPlainChars) {
      _snack('That text is too long. Split it into two blocks.');
      return;
    }
    if (clean.changed) _snack('Some formatting is not supported here and was removed.');
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(planningV2EntryProvider(widget.args).notifier)
          .saveText(widget.block.id, _baseVersion, clean.ops);
      if (!mounted) return;
      switch (result) {
        case TextSaved():
          _dirty = false;
          Navigator.of(context).pop();
        case TextGone():
          _dirty = false;
          _snack('Your partner removed this block.');
          Navigator.of(context).pop();
        case TextConflict(:final theirs):
          await _resolve(theirs, clean.ops);
      }
    } catch (e) {
      if (mounted) showPlanningV2Error(context, e); // draft stays; _dirty unchanged
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resolve(PlanningBlock theirs, List<Map<String, dynamic>> mine) async {
    final choice = await showConflictSheet(context, theirs: theirs.plainText ?? '');
    if (!mounted || choice == null) return;
    switch (choice) {
      case ConflictChoice.keepMine:
        _baseVersion = theirs.version;
        await _save();
      case ConflictChoice.copyMine:
        await Clipboard.setData(ClipboardData(text: deltaPlainText(mine)));
        if (mounted) _snack('Your text is copied.');
        _useTheirs(theirs);
      case ConflictChoice.useTheirs:
        _useTheirs(theirs);
    }
  }

  void _useTheirs(PlanningBlock theirs) {
    final old = _controller;
    setState(() {
      _controller = _load(theirs.delta);
      _baseVersion = theirs.version;
      _dirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  Future<void> _pickToken({required bool background}) async {
    final brightness = Theme.of(context).brightness;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Wrap(alignment: WrapAlignment.center, spacing: Spacing.sm, children: [
          for (final t in tokens)
            Tooltip(
              message: '${background ? 'Highlight' : 'Text'} $t',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(c, t),
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: background
                          ? planningV2HighlightPalette(brightness)[t]
                          : planningV2TextTone(t, brightness),
                    ),
                  ),
                ),
              ),
            ),
          TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('None')),
        ]),
      ),
    );
    if (picked == null) return;
    final value = picked.isEmpty ? null : picked;
    _controller.formatSelection(background ? BackgroundAttribute(value) : ColorAttribute(value));
  }

  Future<bool> _confirmDiscard() => planningV2Confirm(
        context,
        title: 'Discard changes?',
        message: 'Your edits to this text are not saved.',
        confirmText: 'Discard',
        destructive: true,
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmDiscard() && context.mounted) {
            _dirty = false;
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Edit text'),
            actions: [
              TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
            ],
          ),
          body: planningQuillScope(
            context,
            Column(children: [
              QuillSimpleToolbar(
                controller: _controller,
                config: QuillSimpleToolbarConfig(
                  multiRowsDisplay: false,
                  showFontFamily: false,
                  showFontSize: false,
                  showSmallButton: false,
                  showLineHeightButton: false,
                  showInlineCode: false,
                  showColorButton: false,
                  showBackgroundColorButton: false,
                  showListCheck: false,
                  showCodeBlock: false,
                  showIndent: false,
                  showDirection: false,
                  showSearchButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showLeftAlignment: false,
                  showClipboardCut: false,
                  showClipboardCopy: false,
                  showClipboardPaste: false,
                  customButtons: [
                    QuillToolbarCustomButtonOptions(
                      icon: const Tooltip(message: 'Highlight', child: Icon(Icons.format_color_fill_rounded)),
                      onPressed: () => _pickToken(background: true),
                    ),
                    QuillToolbarCustomButtonOptions(
                      icon: const Tooltip(message: 'Text colour', child: Icon(Icons.format_color_text_rounded)),
                      onPressed: () => _pickToken(background: false),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: QuillEditor.basic(
                  controller: _controller,
                  config: planningQuillEditorConfig(context, placeholder: 'Write something…', expands: true),
                ),
              ),
            ]),
          ),
        ),
      );
}
