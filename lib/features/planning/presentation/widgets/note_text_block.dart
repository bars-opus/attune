import 'dart:async';
import 'dart:convert';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/delta_sanitizer.dart';
import 'conflict_sheet.dart';
import 'planning_doc_scope.dart';
import 'planning_quill.dart';

/// What a save came to.
sealed class NoteSaveResult {
  const NoteSaveResult();
}

final class NoteSaved extends NoteSaveResult {
  const NoteSaved({required this.version, this.plainText});
  final int version;
  final String? plainText;
}

/// The block was removed elsewhere.
final class NoteGone extends NoteSaveResult {
  const NoteGone();
}

/// Someone (a partner, or this person on another device) saved first.
final class NoteConflict extends NoteSaveResult {
  const NoteConflict({required this.ops, required this.version, required this.plainText});
  final List<Map<String, dynamic>> ops;
  final int version;
  final String plainText;
}

/// Where a text block's words go — a couple's plan, or a private journal.
/// The block itself only edits, debounces and resolves conflicts.
abstract class NoteTextSaver {
  int get maxPlainChars;
  int get maxPayloadBytes;

  /// Said when the block turns out to be gone.
  String get goneMessage;

  /// The conflict sheet's title.
  String get conflictTitle;

  /// Called from the block's build: watch whatever the saver needs.
  void watch(WidgetRef ref) {}

  Future<NoteSaveResult> save(String blockId, int version, List<Map<String, dynamic>> ops);

  /// The page is closing: save without the page's (closing) state.
  void saveOnLeave(String blockId, int version, List<Map<String, dynamic>> ops);

  /// After a save went through (e.g. title a new note from its first line).
  Future<void> afterSave(String? plainText) async {}

  void showError(BuildContext context, Object error);
}

/// A text block edited in place, like a paragraph in a document. Typing
/// saves itself a second after you stop, when the cursor leaves the block,
/// and when the page closes. A newer save from elsewhere meets the
/// conflict sheet: keep mine, copy mine, or use theirs.
class NoteTextBlock extends ConsumerStatefulWidget {
  const NoteTextBlock({
    super.key,
    required this.blockId,
    required this.delta,
    required this.version,
    required this.saverFor,
    this.autofocus = false,
    this.placeholder = 'Write something…',
  });
  final String blockId;
  final List<Map<String, dynamic>> delta;
  final int version;
  final NoteTextSaver Function(WidgetRef ref) saverFor;
  final bool autofocus;
  final String placeholder;

  static const debounce = Duration(seconds: 1);

  @override
  ConsumerState<NoteTextBlock> createState() => NoteTextBlockState();
}

class NoteTextBlockState extends ConsumerState<NoteTextBlock> {
  late QuillController _controller = _load(widget.delta);
  late int _baseVersion = widget.version;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final NoteTextSaver _saver;
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
    _saver = widget.saverFor(ref);
    _focus.addListener(_onFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final first = _doc == null;
    _doc = PlanningDocScope.read(context);
    _doc?.reportText(widget.blockId, _controller.document.toPlainText().trim().isNotEmpty);
    if (first && (widget.autofocus || (_doc?.takeFocus(widget.blockId) ?? false))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        _controller.moveCursorToEnd();
      });
    }
  }

  /// A newer version from elsewhere (or a split) arrives: show it, unless
  /// there is typing here not yet saved — that meets the conflict sheet on
  /// its next save instead of vanishing.
  @override
  void didUpdateWidget(NoteTextBlock old) {
    super.didUpdateWidget(old);
    if (widget.version != _baseVersion && !_dirty && _saving == null) {
      final previous = _controller;
      _controller = _load(widget.delta);
      _baseVersion = widget.version;
      _register();
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_dirty) _saveOnLeave(); // closing the page saves what was typed
    _doc?.forget(widget.blockId);
    _focus.dispose();
    _scroll.dispose();
    _changes?.cancel();
    final c = _controller;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    super.dispose();
  }

  void _register() {
    if (_doc?.active?.blockId == widget.blockId || _focus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _doc?.activate(PlanningActiveText(
            blockId: widget.blockId, controller: _controller, version: () => _baseVersion, flush: flush));
      });
    }
  }

  bool _tooBig(SanitizedDelta clean) {
    final bytes = utf8.encode(jsonEncode({'delta': clean.ops})).length;
    return deltaPlainText(clean.ops).runes.length > _saver.maxPlainChars || bytes > _saver.maxPayloadBytes;
  }

  void _saveOnLeave() {
    final clean = sanitizeDelta(_controller.document.toDelta().toJson());
    if (_tooBig(clean)) return;
    _saver.saveOnLeave(widget.blockId, _baseVersion, clean.ops);
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _doc?.activate(PlanningActiveText(
          blockId: widget.blockId, controller: _controller, version: () => _baseVersion, flush: flush));
    } else if (_dirty) {
      _debounce?.cancel();
      unawaited(_save());
    }
  }

  void _onTyped() {
    _dirty = true;
    _doc?.reportText(widget.blockId, _controller.document.toPlainText().trim().isNotEmpty);
    _debounce?.cancel();
    _debounce = Timer(NoteTextBlock.debounce, () => unawaited(_save()));
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
    // Two server limits apply: characters of text AND payload bytes. Non-Latin
    // text and emoji reach the byte cap first.
    if (_tooBig(clean)) {
      if (!quiet && mounted) context.showWarningSnackbar('That text is too long to save. Split it into two blocks.');
      return false;
    }
    if (clean.changed && !quiet) _snack('Some formatting is not supported here and was removed.');
    _dirty = false;
    try {
      final result = await _saver.save(widget.blockId, _baseVersion, clean.ops);
      switch (result) {
        case NoteSaved(:final version, :final plainText):
          _baseVersion = version;
          await _saver.afterSave(plainText);
          return true;
        case NoteGone():
          if (!quiet) _snack(_saver.goneMessage);
          return false;
        case NoteConflict():
          _dirty = true;
          if (quiet || !mounted) return false;
          return _resolve(result, clean.ops);
      }
    } catch (e) {
      _dirty = true; // the draft stays on screen and saves on the next pause
      if (!quiet && mounted) _saver.showError(context, e);
      return false;
    }
  }

  Future<bool> _resolve(NoteConflict theirs, List<Map<String, dynamic>> mine) async {
    final choice = await showConflictSheet(context, theirs: theirs.plainText, title: _saver.conflictTitle);
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

  void _useTheirs(NoteConflict theirs) {
    final old = _controller;
    setState(() {
      _controller = _load(theirs.ops);
      _baseVersion = theirs.version;
      _dirty = false;
    });
    _register();
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    _saver.watch(ref);
    return planningQuillScope(
      context,
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: QuillEditor(
          controller: _controller,
          focusNode: _focus,
          scrollController: _scroll,
          config: planningQuillEditorConfig(context, placeholder: widget.placeholder, editable: true),
        ),
      ),
    );
  }
}
