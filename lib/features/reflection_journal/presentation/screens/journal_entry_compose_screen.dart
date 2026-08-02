// lib/features/reflection_journal/presentation/screens/journal_entry_compose_screen.dart
import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reflection_journal/data/journal_prompts.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JournalEntryComposeScreen extends ConsumerStatefulWidget {
  const JournalEntryComposeScreen({super.key, this.entryId});

  final String? entryId;

  @override
  ConsumerState<JournalEntryComposeScreen> createState() =>
      _JournalEntryComposeScreenState();
}

class _JournalEntryComposeScreenState
    extends ConsumerState<JournalEntryComposeScreen> {
  final _controller = TextEditingController();
  bool _promptDismissed = false;
  bool _isSaving = false;
  String? _promptUsed;
  bool _loadedExisting = false;

  @override
  void initState() {
    super.initState();
    _promptUsed = randomJournalPrompt();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      if (widget.entryId != null) {
        await ref.read(
          updateJournalEntryProvider((
            entryId: widget.entryId!,
            content: content,
          )).future,
        );
        unawaited(
          ref.read(analyseJournalEntryProvider(widget.entryId!).future),
        );
      } else {
        final newId = await ref.read(
          createJournalEntryProvider((
            content: content,
            promptUsed: _promptDismissed ? null : _promptUsed,
          )).future,
        );
        unawaited(ref.read(analyseJournalEntryProvider(newId).future));
      }
      if (mounted) {
        context.showSuccessSnackbar('Saved. Sit with that for a bit.');
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (widget.entryId != null && !_loadedExisting) {
      final entryAsync = ref.watch(journalEntryProvider(widget.entryId!));
      entryAsync.whenData((entry) {
        if (!_loadedExisting) {
          _controller.text = entry.content;
          _loadedExisting = true;
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.entryId != null ? 'Edit entry' : 'New entry',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.entryId == null &&
                !_promptDismissed &&
                _promptUsed != null)
              Container(
                padding: EdgeInsets.all(Spacing.smMd.w),
                margin: EdgeInsets.only(bottom: Spacing.md.h),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(
                    BorderRadiusTokens.md.r,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_promptUsed!, style: textTheme.bodyMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _promptDismissed = true),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Write freely. This stays private.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
