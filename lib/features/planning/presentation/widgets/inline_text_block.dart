import 'dart:async';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'dart:convert';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_models.dart';
import '../../data/planning_repository.dart';
import '../../domain/code_point_limit.dart';
import '../../domain/delta_sanitizer.dart';
import '../../domain/planning_limits.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';
import 'conflict_sheet.dart';
import 'planning_doc_scope.dart';
import 'planning_quill.dart';

/// A text block edited in place on the plan's page, like a paragraph in a
/// document. Typing saves itself a second after you stop, when the cursor
/// leaves the block, and when the plan closes. A partner's newer save is
/// handled as before: keep mine, copy mine, or use theirs.
class InlineTextBlock extends ConsumerStatefulWidget {
  const InlineTextBlock({super.key, required this.args, required this.block, this.autofocus = false});
  final PlanningEntryArgs args;
  final PlanningBlock block;
  final bool autofocus;

  static const debounce = Duration(seconds: 1);

  @override
  ConsumerState<InlineTextBlock> createState() => InlineTextBlockState();
}

class InlineTextBlockState extends ConsumerState<InlineTextBlock> {
  late QuillController _controller = _load(widget.block.delta);
  late int _baseVersion = widget.block.version;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final PlanningEntryController _ctl = ref.read(planningEntryProvider(widget.args).notifier);
  // Captured up front: leaving the plan disposes its controller before this
  // block's last save runs, so that save goes straight to the repository.
  late final PlanningRepository _repo;
  PlanningEntry? _entry;
  PlanningDocController? _doc;
  StreamSubscription<DocChange>? _changes;
  Timer? _debounce;
  bool _dirty = false;
  Future<bool>? _saving;

  @visibleForTesting
  QuillController get controller => _controller;

  QuillController _load(List<Map<String, dynamic>> ops) {
    _changes?.cancel();
    final c = QuillController(
      document: Document.fromJson(sanitizeDelta(ops).ops),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _changes = c.document.changes.listen((_) => _onTyped());
    return c;
  }

  @override
  void initState() {
    super.initState();
    _repo = ref.read(planningRepositoryProvider);
    _focus.addListener(_onFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final first = _doc == null;
    _doc = PlanningDocScope.read(context);
    _doc?.reportText(widget.block.id, _controller.document.toPlainText().trim().isNotEmpty);
    if (first && (widget.autofocus || (_doc?.takeFocus(widget.block.id) ?? false))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        _controller.moveCursorToEnd();
      });
    }
  }

  /// A partner's save (or a split) arrives as a newer version: show it,
  /// unless there is typing here not yet saved — that meets the conflict
  /// sheet on its next save instead of vanishing.
  @override
  void didUpdateWidget(InlineTextBlock old) {
    super.didUpdateWidget(old);
    if (widget.block.version != _baseVersion && !_dirty && _saving == null) {
      final previous = _controller;
      _controller = _load(widget.block.delta);
      _baseVersion = widget.block.version;
      _register();
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_dirty) _saveOnLeave(); // closing the plan saves what was typed
    _doc?.forget(widget.block.id);
    _focus.dispose();
    _scroll.dispose();
    _changes?.cancel();
    final c = _controller;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    super.dispose();
  }

  /// Points the ribbon at this block's new controller. After the frame:
  /// this runs while the page is building.
  void _register() {
    if (_doc?.active?.blockId == widget.block.id || _focus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _doc?.activate(PlanningActiveText(
            blockId: widget.block.id, controller: _controller, version: () => _baseVersion, flush: flush));
      });
    }
  }

  /// The plan is closing: save what was typed directly, and title a new
  /// note from its first line, without the plan's (closing) controller.
  void _saveOnLeave() {
    final clean = sanitizeDelta(_controller.document.toDelta().toJson());
    final bytes = utf8.encode(jsonEncode({'delta': clean.ops})).length;
    if (deltaPlainText(clean.ops).runes.length > PlanningLimits.textPlainChars ||
        bytes > PlanningLimits.payloadBytes) {
      return;
    }
    final entry = _entry;
    unawaited(_repo
        .updateBlock(id: widget.block.id, version: _baseVersion, payload: {'delta': clean.ops})
        .then((saved) async {
      final title = _firstLine(saved.plainText);
      if (entry != null && entry.categorySeedKey == 'notes' && entry.title == planningNewNoteTitle && title != null) {
        await _repo.updateEntry(id: entry.id, title: title, status: entry.status);
      }
    }).then((_) {}, onError: (Object _) {})); // a partner's newer save wins; nothing to show on a closed page
  }

  static String? _firstLine(String? text) {
    final line = (text ?? '').split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return line.isEmpty ? null : truncateCodePoints(line, PlanningLimits.titleChars);
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _doc?.activate(PlanningActiveText(
          blockId: widget.block.id, controller: _controller, version: () => _baseVersion, flush: flush));
    } else if (_dirty) {
      _debounce?.cancel();
      unawaited(_save());
    }
  }

  void _onTyped() {
    _dirty = true;
    _doc?.reportText(widget.block.id, _controller.document.toPlainText().trim().isNotEmpty);
    _debounce?.cancel();
    _debounce = Timer(InlineTextBlock.debounce, () => unawaited(_save()));
  }

  /// Saves now if anything is waiting. True when the text on screen is saved.
  Future<bool> flush() async {
    _debounce?.cancel();
    if (_saving != null) await _saving;
    return _dirty ? _save() : true;
  }

  void _snack(String message) {
    if (mounted) context.showInfoSnackbar(message);
  }

  Future<bool> _save({bool quiet = false}) {
    final running = _saving;
    if (running != null) return running.then((_) => _dirty ? _save(quiet: quiet) : true);
    final f = _saveOnce(quiet: quiet);
    _saving = f;
    return f.whenComplete(() => _saving = null);
  }

  Future<bool> _saveOnce({required bool quiet}) async {
    final clean = sanitizeDelta(_controller.document.toDelta().toJson());
    // Two server limits apply: 10,000 characters of text AND a 16 KB payload.
    // Non-Latin text and emoji reach the byte cap first (final review I3).
    final bytes = utf8.encode(jsonEncode({'delta': clean.ops})).length;
    if (deltaPlainText(clean.ops).runes.length > PlanningLimits.textPlainChars ||
        bytes > PlanningLimits.payloadBytes) {
      if (!quiet && mounted) context.showWarningSnackbar('That text is too long to save. Split it into two blocks.');
      return false;
    }
    if (clean.changed && !quiet) _snack('Some formatting is not supported here and was removed.');
    _dirty = false;
    try {
      final result = await _ctl.saveText(widget.block.id, _baseVersion, clean.ops);
      switch (result) {
        case TextSaved(:final block):
          _baseVersion = block.version;
          await _titleNewNote(block);
          return true;
        case TextGone():
          if (!quiet) _snack('Your partner removed this block.');
          return false;
        case TextConflict(:final theirs):
          _dirty = true;
          if (quiet || !mounted) return false;
          return _resolve(theirs, clean.ops);
      }
    } catch (e) {
      _dirty = true; // the draft stays on screen and saves on the next pause
      if (!quiet && mounted) showPlanningError(context, e);
      return false;
    }
  }

  /// A note still called "New note" takes its first non-empty line as its
  /// title. A failed rename never blocks the save; the default title stays.
  Future<void> _titleNewNote(PlanningBlock saved) async {
    final entry = ref.read(planningEntryProvider(widget.args)).valueOrNull?.entry;
    if (entry == null || entry.categorySeedKey != 'notes' || entry.title != planningNewNoteTitle) return;
    final title = _firstLine(saved.plainText);
    if (title == null) return;
    try {
      await _ctl.rename(title);
    } catch (_) {}
  }

  Future<bool> _resolve(PlanningBlock theirs, List<Map<String, dynamic>> mine) async {
    final choice = await showConflictSheet(context, theirs: theirs.plainText ?? '');
    if (!mounted || choice == null) return false;
    switch (choice) {
      case ConflictChoice.keepMine:
        _baseVersion = theirs.version;
        _saving = null;
        return _saveOnce(quiet: false);
      case ConflictChoice.copyMine:
        await Clipboard.setData(ClipboardData(text: deltaPlainText(mine)));
        _snack('Your text is copied.');
        _useTheirs(theirs);
        return true;
      case ConflictChoice.useTheirs:
        _useTheirs(theirs);
        return true;
    }
  }

  void _useTheirs(PlanningBlock theirs) {
    final old = _controller;
    setState(() {
      _controller = _load(theirs.delta);
      _baseVersion = theirs.version;
      _dirty = false;
    });
    _register();
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    _entry = ref.watch(planningEntryProvider(widget.args).select((a) => a.valueOrNull?.entry));
    return _editor(context);
  }

  Widget _editor(BuildContext context) => planningQuillScope(
        context,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: QuillEditor(
            controller: _controller,
            focusNode: _focus,
            scrollController: _scroll,
            config: planningQuillEditorConfig(context, placeholder: 'Write something…', editable: true),
          ),
        ),
      );
}
