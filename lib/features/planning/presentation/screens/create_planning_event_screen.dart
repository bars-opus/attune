// lib/features/planning/presentation/screens/create_planning_event_screen.dart
//
// Does not yet offer linking existing Tasks to the Event being
// created — spec §6.2's Event edit flow includes a picker for existing
// live top-level Tasks, which needs list_planning_tasks already loaded
// and a multi-select UI; deferred to a dedicated follow-up on top of
// this plan rather than folded into first creation, since a brand-new
// Event has no Tasks worth linking yet in the common case (create the
// event, add/link tasks afterward from Planning home).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/cupertino_date_time_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../providers/planning_providers.dart';

class CreatePlanningEventScreen extends ConsumerStatefulWidget {
  const CreatePlanningEventScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<CreatePlanningEventScreen> createState() => _CreatePlanningEventScreenState();
}

class _CreatePlanningEventScreenState extends ConsumerState<CreatePlanningEventScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _eventDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // The date is REQUIRED for an event (upsert_planning_event rejects a
  // null p_event_date), unlike a Task's optional due date.
  bool get _canSave =>
      _titleController.text.trim().isNotEmpty && _eventDate != null && !_isSaving;

  Future<void> _pickEventDate() {
    return showCupertinoDateTimeSheet(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: _eventDate ?? DateTime.now(),
      onChanged: (value) => setState(() => _eventDate = value),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.upsertEvent(
        id: const Uuid().v4(),
        relationshipId: widget.relationshipId,
        title: _titleController.text.trim(),
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        eventDate: _eventDate!,
      );
      ref.read(planningEventsProvider(
        PlanningEventsKey(relationshipId: widget.relationshipId, upcoming: true),
      ).notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the event. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New event')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Event'),
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
                _eventDate == null
                    ? 'Pick a date'
                    : DateFormat.yMMMd().format(_eventDate!),
              ),
              trailing: TextButton(
                onPressed: _pickEventDate,
                child: Text(_eventDate == null ? 'Set date' : 'Change'),
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
