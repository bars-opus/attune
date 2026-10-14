import 'dart:async';

import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/reflection_journal_repository.dart';
import '../providers/reflection_journal_providers.dart';

/// One visit to an entry: the saves still landing as the page closes, and
/// whether any text changed (the reflection runs once, after, if so).
class JournalVisit {
  final List<Future<void>> _pending = [];
  bool textChanged = false;

  void track(Future<void> f) => _pending.add(f.then((_) {}, onError: (Object _) {}));

  Future<void> settled() => Future.wait(List.of(_pending));
}

/// A journal text block's words go to the owner's own entry.
class JournalTextSaver extends NoteTextSaver {
  JournalTextSaver(WidgetRef ref, this._entryId, {required this.visit, required this.titleFromFirstLine})
    : _ctl = ref.read(journalEntryDetailProvider(_entryId).notifier),
      _repo = ref.read(reflectionJournalRepositoryProvider);

  final String _entryId;
  final JournalVisit visit;

  /// True for the entry's first text block while the entry has no title.
  final bool Function() titleFromFirstLine;
  final JournalEntryController _ctl;

  // Captured up front: closing the entry disposes its controller before the
  // last save runs, so that save goes straight to the repository.
  final ReflectionJournalRepository _repo;

  @override
  int get maxPlainChars => 10000;
  @override
  int get maxPayloadBytes => 16384;
  @override
  String get goneMessage => 'This part was removed on another device.';
  @override
  String get conflictTitle => 'You changed this on another device';

  /// Tracked by the visit too: leaving while this is on its way waits for
  /// it before reflecting (otherwise the reflection reads the old text).
  @override
  Future<NoteSaveResult> save(String blockId, int version, List<Map<String, dynamic>> ops) {
    final f = _ctl.saveText(blockId, version, ops).then((r) {
      if (r is NoteSaved) visit.textChanged = true;
      return r;
    });
    visit.track(f);
    return f;
  }

  @override
  void saveOnLeave(String blockId, int version, List<Map<String, dynamic>> ops) {
    final titleIt = titleFromFirstLine();
    visit.track(_repo.saveText(blockId, version, ops).then((r) async {
      if (r.status != 'saved') return;
      visit.textChanged = true;
      final title = firstLine(r.block.plainText);
      if (titleIt && title != null) await _repo.rename(_entryId, title);
    }));
  }

  @override
  Future<void> afterSave(String? plainText) async {
    if (!titleFromFirstLine()) return;
    final title = firstLine(plainText);
    if (title == null) return;
    try {
      await _ctl.rename(title);
    } catch (_) {}
  }

  @override
  void showError(BuildContext context, Object error) =>
      context.showErrorSnackbar(error is JournalTooLong ? 'That text is too long to save.' : "Couldn't save. We'll try again.");

  static String? firstLine(String? text) {
    final line = (text ?? '').split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (line.isEmpty) return null;
    final runes = line.runes.toList();
    return runes.length <= 120 ? line : String.fromCharCodes(runes.take(120));
  }
}
