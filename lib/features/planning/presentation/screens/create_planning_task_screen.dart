// lib/features/planning/presentation/screens/create_planning_task_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/cupertino_date_time_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../providers/planning_providers.dart';

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

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSave => _titleController.text.trim().isNotEmpty && !_isSaving;

  Future<void> _pickDueDate() {
    return showCupertinoDateTimeSheet(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: _dueDate ?? DateTime.now(),
      onChanged: (value) => setState(() => _dueDate = value),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
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
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the task. Try again.')),
        );
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
          ],
        ),
      ),
    );
  }
}
