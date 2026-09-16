// lib/features/planning/presentation/screens/create_planning_goal_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../providers/planning_providers.dart';

/// Save is disabled until BOTH the goal title and the first task title
/// are non-blank (spec §6.2) — create_planning_goal (Plan A) requires
/// both in the same call; there is no code path that creates a
/// zero-child goal.
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

  @override
  void dispose() {
    _goalTitleController.dispose();
    _firstTaskTitleController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _goalTitleController.text.trim().isNotEmpty &&
      _firstTaskTitleController.text.trim().isNotEmpty &&
      !_isSaving;

  Future<void> _save() async {
    setState(() => _isSaving = true);
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
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the goal. Try again.')),
        );
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
          ],
        ),
      ),
    );
  }
}
