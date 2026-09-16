// lib/features/planning/presentation/screens/create_planning_goal_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/planning_error.dart';
import '../providers/planning_providers.dart';

/// Save is disabled until BOTH the goal title and the first task title
/// are non-blank (spec §6.2) — create_planning_goal (Plan A) requires
/// both in the same call; there is no code path that creates a
/// zero-child goal.
///
/// On a failed save, the draft stays exactly as typed. Whether Save
/// itself stays available to retry depends on WHICH `PlanningError`
/// came back: a transient/network failure keeps Save enabled, but
/// `PlanningUnauthorizedError` fails closed per its own doc comment
/// ("must fail closed... never retry automatically") — matching the
/// typed-error dispatch `planning_note_editor_screen.dart` (Task 4)
/// and `planning_home_screen.dart` (Task 3) already established for
/// this feature rather than a bare `catch (_)` with one generic,
/// always-retryable message for every failure.
class CreatePlanningGoalScreen extends ConsumerStatefulWidget {
  const CreatePlanningGoalScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<CreatePlanningGoalScreen> createState() => _CreatePlanningGoalScreenState();
}

class _CreatePlanningGoalScreenState extends ConsumerState<CreatePlanningGoalScreen> {
  final _goalTitleController = TextEditingController();
  final _firstTaskTitleController = TextEditingController();
  bool _isSaving = false;
  // Set only for PlanningUnauthorizedError: Save must not offer retry
  // for a failure the repository has already told us is not transient.
  bool _saveDisabledFailedClosed = false;
  String? _errorMessage;

  @override
  void dispose() {
    _goalTitleController.dispose();
    _firstTaskTitleController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _goalTitleController.text.trim().isNotEmpty &&
      _firstTaskTitleController.text.trim().isNotEmpty &&
      !_isSaving &&
      !_saveDisabledFailedClosed;

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final repository = ref.read(planningRepositoryProvider);
    const uuid = Uuid();
    try {
      await repository.createGoal(
        goalId: uuid.v4(),
        firstTaskId: uuid.v4(),
        relationshipId: widget.relationshipId,
        goalTitle: _goalTitleController.text.trim(),
        firstTaskTitle: _firstTaskTitleController.text.trim(),
      );
      ref.read(planningGoalsProvider(widget.relationshipId).notifier).refresh();
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
            _errorMessage = 'Could not create the goal. Try again.';
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
      appBar: AppBar(title: const Text('New goal')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _goalTitleController,
              decoration: const InputDecoration(labelText: 'Goal'),
              onChanged: (_) => setState(() {}),
              autofocus: true,
            ),
            SizedBox(height: Spacing.md),
            TextField(
              controller: _firstTaskTitleController,
              decoration: const InputDecoration(labelText: 'First task'),
              onChanged: (_) => setState(() {}),
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
