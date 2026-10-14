import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_models.dart';
import '../../data/planning_repository.dart';
import '../../domain/code_point_limit.dart';
import '../../domain/planning_limits.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';
import 'note_text_block.dart';

/// A text block edited in place on the plan's page, like a paragraph in a
/// document. A partner's newer save is handled as before: keep mine, copy
/// mine, or use theirs. (The editing itself is [NoteTextBlock].)
class InlineTextBlock extends NoteTextBlock {
  InlineTextBlock({super.key, required this.args, required this.block, super.autofocus})
    : super(
        blockId: block.id,
        delta: block.delta,
        version: block.version,
        saverFor: (ref) => PlanningTextSaver(ref, args),
      );
  final PlanningEntryArgs args;
  final PlanningBlock block;

  static const debounce = NoteTextBlock.debounce;
}

/// The state's old name, kept for the Planning tests that reach into it.
typedef InlineTextBlockState = NoteTextBlockState;

class PlanningTextSaver extends NoteTextSaver {
  PlanningTextSaver(this._ref, this._args)
    : _ctl = _ref.read(planningEntryProvider(_args).notifier),
      _repo = _ref.read(planningRepositoryProvider);

  final WidgetRef _ref;
  final PlanningEntryArgs _args;
  final PlanningEntryController _ctl;

  // Captured up front: leaving the plan disposes its controller before this
  // block's last save runs, so that save goes straight to the repository.
  final PlanningRepository _repo;
  PlanningEntry? _entry;

  @override
  int get maxPlainChars => PlanningLimits.textPlainChars;
  @override
  int get maxPayloadBytes => PlanningLimits.payloadBytes;
  @override
  String get goneMessage => 'Your partner removed this block.';
  @override
  String get conflictTitle => 'Your partner just changed this';

  @override
  void watch(WidgetRef ref) {
    _entry = ref.watch(planningEntryProvider(_args).select((a) => a.valueOrNull?.entry));
  }

  @override
  Future<NoteSaveResult> save(String blockId, int version, List<Map<String, dynamic>> ops) async {
    final result = await _ctl.saveText(blockId, version, ops);
    return switch (result) {
      TextSaved(:final block) => NoteSaved(version: block.version, plainText: block.plainText),
      TextGone() => const NoteGone(),
      TextConflict(:final theirs) =>
        NoteConflict(ops: theirs.delta, version: theirs.version, plainText: theirs.plainText ?? ''),
    };
  }

  /// The plan is closing: save what was typed directly, and title a new
  /// note from its first line, without the plan's (closing) controller.
  @override
  void saveOnLeave(String blockId, int version, List<Map<String, dynamic>> ops) {
    final entry = _entry;
    unawaited(_repo.updateBlock(id: blockId, version: version, payload: {'delta': ops}).then((saved) async {
      final title = firstLine(saved.plainText);
      if (entry != null && entry.categorySeedKey == 'notes' && entry.title == planningNewNoteTitle && title != null) {
        await _repo.updateEntry(id: entry.id, title: title, status: entry.status);
      }
    }).then((_) {}, onError: (Object _) {})); // a partner's newer save wins; nothing to show on a closed page
  }

  /// A note still called "New note" takes its first non-empty line as its
  /// title. A failed rename never blocks the save; the default title stays.
  @override
  Future<void> afterSave(String? plainText) async {
    final entry = _ref.read(planningEntryProvider(_args)).valueOrNull?.entry;
    if (entry == null || entry.categorySeedKey != 'notes' || entry.title != planningNewNoteTitle) return;
    final title = firstLine(plainText);
    if (title == null) return;
    try {
      await _ctl.rename(title);
    } catch (_) {}
  }

  @override
  void showError(BuildContext context, Object error) => showPlanningError(context, error);

  static String? firstLine(String? text) {
    final line = (text ?? '').split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return line.isEmpty ? null : truncateCodePoints(line, PlanningLimits.titleChars);
  }
}
