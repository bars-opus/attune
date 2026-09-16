// lib/features/planning/presentation/screens/create_planning_task_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/cupertino_date_time_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/planning_error.dart';
import '../providers/planning_providers.dart';

/// On a failed save, the draft stays exactly as typed. Whether Save
/// itself stays available to retry depends on WHICH `PlanningError`
/// came back: a transient/network failure keeps Save enabled, but
/// `PlanningUnauthorizedError` fails closed per its own doc comment
/// ("must fail closed... never retry automatically") — matching the
/// typed-error dispatch `planning_note_editor_screen.dart` (Task 4)
/// and `planning_home_screen.dart` (Task 3) already established for
/// this feature rather than a bare `catch (_)` with one generic,
/// always-retryable message for every failure.
class CreatePlanningTaskScreen extends ConsumerStatefulWidget {
  const CreatePlanningTaskScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<CreatePlanningTaskScreen> createState() => _CreatePlanningTaskScreenState();
}

class _CreatePlanningTaskScreenState extends ConsumerState<CreatePlanningTaskScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _dueDate;
  bool _isSaving = false;
  // Set only for PlanningUnauthorizedError: Save must not offer retry
  // for a failure the repository has already told us is not transient.
  bool _saveDisabledFailedClosed = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _titleController.text.trim().isNotEmpty &&
      !_isSaving &&
      !_saveDisabledFailedClosed;

  Future<void> _pickDueDate() {
    return showCupertinoDateTimeSheet(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: _dueDate ?? DateTime.now(),
      onChanged: (value) => setState(() => _dueDate = value),
    );
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.createTask(
        id: const Uuid().v4(),
        relationshipId: widget.relationshipId,
        title: _titleController.text.trim(),
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        dueDate: _dueDate,
      );
      ref.read(planningTasksProvider(widget.relationshipId).notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    } on PlanningError catch (error) {
      if (!mounted) return;
      switch (error) {
        case PlanningUnauthorizedError():
          // Fail closed: not transient, so no retry affordance.
          setState(() {
            _isSaving = false;
            _saveDisabledFailedClosed = true;
            _errorMessage = 'Planning is no longer available for this relationship.';
          });
        case PlanningNetworkError():
          setState(() {
            _isSaving = false;
            _errorMessage = 'Could not create the task. Try again.';
          });
        case PlanningNotFoundError():
          setState(() {
            _isSaving = false;
            _errorMessage = 'This item no longer exists.';
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
      appBar: AppBar(title: const Text('New task')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Task'),
              onChanged: (_) => setState(() {}),
              autofocus: true,
            ),
            SizedBox(height: Spacing.md),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            SizedBox(height: Spacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _dueDate == null
                    ? 'No due date'
                    : DateFormat.yMMMd().format(_dueDate!),
              ),
              trailing: TextButton(
                onPressed: _pickDueDate,
                child: Text(_dueDate == null ? 'Set date' : 'Change'),
              ),
            ),
            SizedBox(height: Spacing.lg),
            ElevatedButton(
              onPressed: _canSave ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
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
