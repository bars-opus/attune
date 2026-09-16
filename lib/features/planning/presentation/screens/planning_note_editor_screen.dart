// lib/features/planning/presentation/screens/planning_note_editor_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/planning_error.dart';
import '../../data/models/planning_note_model.dart';
import '../providers/planning_providers.dart';

/// Save is explicit (spec §6.3) — no autosave-on-every-keystroke. On a
/// failed save, the draft text stays exactly as typed so the user never
/// loses what they wrote. Whether Save itself stays available to retry
/// depends on WHICH `PlanningError` came back: a transient/network
/// failure keeps Save enabled (spec allows automatic retry-by-tapping
/// there), but `PlanningUnauthorizedError` fails closed per its own doc
/// comment ("must fail closed... never retry automatically") — Save is
/// disabled and the message makes clear retrying will not help,
/// matching the typed-error dispatch `planning_home_screen.dart`
/// (Task 3) already established for this feature rather than a bare
/// `catch (_)` with one generic message for every failure.
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
  // Set only for PlanningUnauthorizedError: Save must not offer retry
  // for a failure the repository has already told us is not transient
  // (the relationship ended / access was revoked while editing).
  bool _saveDisabledFailedClosed = false;

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
    } on PlanningError catch (error) {
      // Draft text is untouched either way — the controllers still
      // hold exactly what the user typed. What differs by error type
      // is whether Save stays available to retry.
      if (!mounted) return;
      switch (error) {
        case PlanningUnauthorizedError():
          // Fail closed: this is not transient, so no retry
          // affordance. The draft stays visible (the user may still
          // want to copy it out) but Save is disabled — tapping it
          // again cannot succeed and must not be offered as if it
          // could.
          setState(() {
            _isSaving = false;
            _saveDisabledFailedClosed = true;
            _errorMessage = 'Planning is no longer available for this relationship.';
          });
        case PlanningNetworkError():
          setState(() {
            _isSaving = false;
            _errorMessage = 'Could not save. Try again.';
          });
        case PlanningNotFoundError():
          setState(() {
            _isSaving = false;
            _errorMessage = 'This note no longer exists.';
          });
        case PlanningValidationError(message: final message):
          setState(() {
            _isSaving = false;
            _errorMessage = message;
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
            onPressed: (_isSaving || _saveDisabledFailedClosed) ? null : _save,
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
