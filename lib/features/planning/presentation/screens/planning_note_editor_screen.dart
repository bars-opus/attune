// lib/features/planning/presentation/screens/planning_note_editor_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/planning_note_model.dart';
import '../providers/planning_providers.dart';

/// Save is explicit (spec §6.3) — no autosave-on-every-keystroke. On a
/// failed save, the draft text stays exactly as typed and Save remains
/// available to retry; nothing here clears the TextField on failure.
class PlanningNoteEditorScreen extends ConsumerStatefulWidget {
  const PlanningNoteEditorScreen({
    super.key,
    required this.relationshipId,
    this.existingNote,
  });
  final String relationshipId;
  final PlanningNoteModel? existingNote;

  @override
  ConsumerState<PlanningNoteEditorScreen> createState() => _PlanningNoteEditorScreenState();
}

class _PlanningNoteEditorScreenState extends ConsumerState<PlanningNoteEditorScreen> {
  late final _titleController = TextEditingController(text: widget.existingNote?.title ?? '');
  late final _bodyController = TextEditingController(text: widget.existingNote?.body ?? '');
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.upsertNote(
        id: widget.existingNote?.id ?? const Uuid().v4(),
        relationshipId: widget.relationshipId,
        title: _titleController.text.trim(),
        body: _bodyController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Draft text is untouched — the controllers still hold exactly
      // what the user typed, ready to retry.
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Could not save. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingNote == null ? 'New note' : 'Edit note'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              autofocus: widget.existingNote == null,
            ),
            SizedBox(height: Spacing.smMd),
            Expanded(
              child: TextField(
                controller: _bodyController,
                decoration: const InputDecoration(labelText: 'Note'),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
              ),
            ),
            if (_errorMessage != null)
              Padding(
                padding: EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
