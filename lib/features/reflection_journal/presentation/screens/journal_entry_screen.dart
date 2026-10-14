import 'dart:async';
import 'dart:typed_data';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/planning/domain/code_point_limit.dart';
import 'package:attune/features/planning/domain/delta_sanitizer.dart';
import 'package:attune/features/planning/data/planning_models.dart' show PlanningBlockType;
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/planning/presentation/widgets/photo_block_view.dart' show planningPhotoPickerProvider;
import 'package:attune/features/planning/presentation/widgets/planning_doc_scope.dart';
import 'package:attune/features/planning/presentation/widgets/planning_ribbon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../data/models/journal_note.dart';
import '../../data/repositories/reflection_journal_repository.dart';
import '../providers/reflection_journal_providers.dart';
import '../widgets/journal_photo_block.dart';
import '../widgets/journal_text_saver.dart';

class JournalEntryArgs {
  const JournalEntryArgs({required this.entryId, this.isNew = false, this.prompt});
  final String entryId;
  final bool isNew;
  final String? prompt;
}

/// What Insert offers in a journal entry.
const journalBlockTools = <(PlanningBlockType, IconData, String)>[
  (PlanningBlockType.text, Icons.notes_rounded, 'Text'),
  (PlanningBlockType.photo, Icons.photo_library_outlined, 'Photo'),
];

enum _EntryMenu { pin, unpin, delete }

enum _BlockMenu { up, down, remove }

/// A journal entry, written like a note: a title, then text and photos.
/// Private to its writer; nothing here reaches a partner.
class JournalEntryScreen extends ConsumerStatefulWidget {
  const JournalEntryScreen({super.key, required this.entryId, this.isNew = false, this.prompt});
  final String entryId;
  final bool isNew;
  final String? prompt;

  @override
  ConsumerState<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends ConsumerState<JournalEntryScreen> {
  final _doc = PlanningDocController();
  final _visit = JournalVisit();
  // Captured while ref is usable: dispose (and the work it schedules) runs
  // after the widget is gone.
  late final ReflectionJournalRepository _repo;
  late final JournalListNotifier _list;
  JournalEntryDetail? _last;
  bool _promptDismissed = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(reflectionJournalRepositoryProvider);
    _list = ref.read(journalListProvider.notifier);
  }

  @override
  void dispose() {
    _doc.dispose();
    // The blocks (children) have already queued their last saves. Once those
    // land: one reflection if any text changed, then a fresher list.
    final visit = _visit;
    final repo = _repo;
    final list = _list;
    final id = widget.entryId;
    scheduleMicrotask(() async {
      await visit.settled();
      if (visit.textChanged) unawaited(repo.analyseEntry(id).then((_) {}, onError: (Object _) {}));
      unawaited(list.refresh());
    });
    super.dispose();
  }

  /// A new entry closed with nothing written, titled or added is removed.
  void _onPop(bool didPop) {
    if (!didPop || !widget.isNew) return;
    final d = _last;
    if (d == null || _doc.anyText || !d.isUntouched) return;
    _list.forget(widget.entryId);
    unawaited(_repo.purgeEntry(widget.entryId).then((_) {}, onError: (Object _) {}));
  }

  JournalEntryController get _ctl => ref.read(journalEntryDetailProvider(widget.entryId).notifier);

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } on JournalLimitReached {
      if (mounted) context.showWarningSnackbar('This entry is full (50 parts, 10 photos).');
    } catch (_) {
      if (mounted) context.showErrorSnackbar("Couldn't do that. Please try again.");
    }
  }

  Future<ImageSource?> _askSource() => showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Camera'),
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Photo library'),
            onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ]),
    ),
  );

  /// Insert, as in a word processor: where the cursor is (splitting the
  /// paragraph mid-way), else after the block last tapped, else at the end.
  Future<void> _insert(PlanningBlockType type) async {
    Map<String, dynamic>? payload;
    if (type == PlanningBlockType.photo) {
      final source = await _askSource();
      if (source == null || !mounted) return;
      final picked = await ref.read(planningPhotoPickerProvider)(source, 1);
      if (!mounted) return;
      if (picked.photos.isEmpty) {
        if (picked.rejected > 0) context.showWarningSnackbar("That photo couldn't be used.");
        return;
      }
      final path = await _upload(picked.photos.first);
      if (path == null) return;
      payload = {'path': path};
    }
    await _place(type == PlanningBlockType.photo ? 'photo' : 'text', payload);
  }

  /// The photo goes up first; only then is its block made (nothing is ever
  /// half-saved). A failure offers Retry.
  Future<String?> _upload(Uint8List jpeg) async {
    final path = _ctl.newPhotoPath();
    try {
      await ref.read(journalMediaGatewayProvider).uploadJpeg(path, jpeg);
      return path;
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar("Couldn't add this photo — try again.", actionLabel: 'Retry', onAction: () async {
          final retried = await _upload(jpeg);
          if (retried != null) await _place('photo', {'path': retried});
        });
      }
      return null;
    }
  }

  Future<void> _place(String kind, Map<String, dynamic>? payload) => _guard(() async {
    final blocks = ref.read(journalEntryDetailProvider(widget.entryId)).valueOrNull?.blocks ?? const <JournalBlock>[];
    final active = _doc.active;
    if (active != null && blocks.any((b) => b.id == active.blockId)) {
      if (!await active.flush()) return;
      final c = active.controller;
      final plain = c.document.toPlainText();
      final at = c.selection.baseOffset.clamp(0, plain.length);
      final added = plain.substring(0, at).trim().isNotEmpty && plain.substring(at).trim().isNotEmpty
          ? await _ctl.insertAtCursor(kind,
              textBlockId: active.blockId,
              version: active.version(),
              before: sanitizeDelta(c.document.toDelta().slice(0, at).toJson()).ops,
              after: sanitizeDelta(c.document.toDelta().slice(at).toJson()).ops,
              payload: payload)
          : await _ctl.addBlock(kind, payload: payload, afterId: active.blockId);
      if (kind == 'text') _doc.focusWhenShown(added.id);
      return;
    }
    final selected = _doc.selectedBlockId;
    final after = blocks.any((b) => b.id == selected) ? selected : null;
    final added = await _ctl.addBlock(kind, payload: payload, afterId: after);
    if (after == null) _doc.revealEnd();
    if (kind == 'text') _doc.focusWhenShown(added.id);
  });

  Future<void> _confirmDelete() async {
    await BottomSheetUtils.showDocumentationBottomSheet(
      // Fits the longer message (photos too) with no overflow; text
      // scaling is capped at 1.0 app-wide.
      maxHeight: 460.h,
      context: context,
      widget: ConfirmationDialog(
        type: ConfirmationType.warning,
        icon: Icons.delete,
        title: 'Delete this entry?',
        message: "This can't be undone. The entry, its photos and its reflection will be permanently removed.",
        confirmText: 'Delete',
        onConfirm: () async {
          try {
            await _repo.purgeEntry(widget.entryId);
          } catch (_) {
            if (mounted) context.showErrorSnackbar("Couldn't delete it. Please try again.");
            return;
          }
          _list.forget(widget.entryId);
          if (mounted) context.pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journalEntryDetailProvider(widget.entryId));
    _last = async.valueOrNull ?? _last;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _onPop(didPop),
      child: PlanningDocScope(
        controller: _doc,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(), // hides the keyboard, which saves
          child: Scaffold(
            appBar: AppBar(
              centerTitle: false,
              actions: [
                if (async.valueOrNull case final d?)
                  PopupMenuButton<_EntryMenu>(
                    tooltip: 'Entry options',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (m) => switch (m) {
                      _EntryMenu.pin => _guard(() => _ctl.setPinned(true)),
                      _EntryMenu.unpin => _guard(() => _ctl.setPinned(false)),
                      _EntryMenu.delete => _confirmDelete(),
                    },
                    itemBuilder: (_) => [
                      if (d.entry.pinnedAt == null)
                        const PopupMenuItem(value: _EntryMenu.pin, child: Text('Pin'))
                      else
                        const PopupMenuItem(value: _EntryMenu.unpin, child: Text('Unpin')),
                      const PopupMenuItem(value: _EntryMenu.delete, child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            body: Column(children: [
              Expanded(
                child: async.when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: ErrorStateWidget(
                      title: "Couldn't open this entry",
                      primaryActionLabel: 'Try again',
                      onPrimaryAction: () => ref.invalidate(journalEntryDetailProvider(widget.entryId)),
                    ),
                  ),
                  data: _page,
                ),
              ),
              if (async.hasValue)
                PlanningRibbon(tools: journalBlockTools, onInsert: (t) => _insert(t)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _page(JournalEntryDetail d) {
    _doc.seed(d.blocks.map((b) => b.id));
    final firstText = d.blocks.where((b) => b.isText).firstOrNull?.id;
    final showPrompt = widget.isNew && widget.prompt != null && !_promptDismissed;
    return ReorderableListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      scrollController: _doc.scroll,
      buildDefaultDragHandles: false,
      padding: Spacing.horizontalMd,
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _TitleField(entryId: widget.entryId, detail: d),
        if (showPrompt)
          _PromptCard(prompt: widget.prompt!, onDismiss: () => setState(() => _promptDismissed = true)),
      ]),
      footer: Column(children: [
        if (d.analysis case final a? when a.status == 'completed' && (a.observation ?? '').isNotEmpty)
          _ReflectionCard(tone: a.tone, observation: a.observation!),
        const SizedBox(height: Spacing.xxl * 2),
      ]),
      itemCount: d.blocks.length,
      onReorder: (from, to) => _guard(() => _ctl.moveBlock(d.blocks[from].id, to > from ? to - 1 : to)),
      itemBuilder: (context, i) {
        final b = d.blocks[i];
        final name = b.isPhoto ? 'photo' : 'text';
        final menu = PopupMenuButton<_BlockMenu>(
          tooltip: 'Options for $name',
          onSelected: (m) => switch (m) {
            _BlockMenu.up => _guard(() => _ctl.moveBlock(b.id, i - 1)),
            _BlockMenu.down => _guard(() => _ctl.moveBlock(b.id, i + 1)),
            _BlockMenu.remove => _guard(() => _ctl.deleteBlock(b.id)),
          },
          itemBuilder: (_) => [
            if (i > 0) const PopupMenuItem(value: _BlockMenu.up, child: Text('Move up')),
            if (i < d.blocks.length - 1) const PopupMenuItem(value: _BlockMenu.down, child: Text('Move down')),
            if (d.blocks.length > 1) const PopupMenuItem(value: _BlockMenu.remove, child: Text('Remove')),
          ],
        );
        final body = b.isText
            ? NoteTextBlock(
                key: ValueKey('text-${b.id}'),
                blockId: b.id,
                delta: b.delta,
                version: b.version,
                autofocus: widget.isNew && b.id == firstText,
                placeholder: 'Write what’s on your mind…',
                saverFor: (ref) => JournalTextSaver(
                  ref,
                  widget.entryId,
                  visit: _visit,
                  titleFromFirstLine: () =>
                      b.id == firstText && (_last?.entry.title ?? '').trim().isEmpty,
                ),
              )
            : JournalPhotoBlock(path: b.photoPath ?? '');
        return ReorderableDelayedDragStartListener(
          key: ValueKey('block-${b.id}'),
          index: i,
          child: GestureDetector(
            onTap: b.isPhoto ? () => _doc.select(b.id) : null,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: body), menu]),
          ),
        );
      },
    );
  }
}

class _TitleField extends ConsumerStatefulWidget {
  const _TitleField({required this.entryId, required this.detail});
  final String entryId;
  final JournalEntryDetail detail;

  @override
  ConsumerState<_TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends ConsumerState<_TitleField> {
  late final _c = TextEditingController(text: widget.detail.entry.title ?? '');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_TitleField old) {
    super.didUpdateWidget(old);
    // Titled from the first line, or renamed on another device.
    final t = widget.detail.entry.title ?? '';
    if (!_focus.hasFocus && t != _c.text) _c.text = t;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _c.text.trim();
    if (t == (widget.detail.entry.title ?? '')) return;
    try {
      await ref.read(journalEntryDetailProvider(widget.entryId).notifier).rename(t.isEmpty ? null : t);
    } catch (_) {
      if (mounted) {
        _c.text = widget.detail.entry.title ?? '';
        context.showErrorSnackbar("Couldn't rename it. Please try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: TextField(
      controller: _c,
      focusNode: _focus,
      style: Theme.of(context).textTheme.headlineSmall,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      inputFormatters: [CodePointLengthFormatter(120)],
      maxLines: null,
      decoration: InputDecoration(
        hintText: DateFormat('EEEE, d MMMM').format(widget.detail.entry.createdAt.toLocal()),
        filled: false,
        fillColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      ),
      onSubmitted: (_) => _focus.unfocus(),
    ),
  );
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt, required this.onDismiss});
  final String prompt;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.xs, Spacing.sm),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadiusTokens.mdAll),
      child: Row(children: [
        Icon(Icons.lightbulb_outline_rounded, color: scheme.primary, size: 20),
        const SizedBox(width: Spacing.sm),
        Expanded(child: Text(prompt, style: Theme.of(context).textTheme.bodyMedium)),
        IconButton(tooltip: 'Dismiss prompt', icon: const Icon(Icons.close_rounded), onPressed: onDismiss),
      ]),
    );
  }
}

class _ReflectionCard extends StatelessWidget {
  const _ReflectionCard({required this.tone, required this.observation});
  final String? tone;
  final String observation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: Spacing.md),
      padding: Spacing.allMd,
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadiusTokens.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('A reflection', style: text.titleSmall),
          if (tone != null) ...[
            const SizedBox(width: Spacing.sm),
            Chip(label: Text(tone!), visualDensity: VisualDensity.compact),
          ],
        ]),
        const SizedBox(height: Spacing.xs),
        Text(observation, style: text.bodyMedium),
      ]),
    );
  }
}
