// lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/timeline/data/repositories/timeline_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddEditReminderScreen extends ConsumerStatefulWidget {
  const AddEditReminderScreen({super.key});

  @override
  ConsumerState<AddEditReminderScreen> createState() => _AddEditReminderScreenState();
}

class _AddEditReminderScreenState extends ConsumerState<AddEditReminderScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  String _reminderType = 'anniversary';
  DateTime _remindAt = DateTime.now();
  bool _isYearly = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _remindAt,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _remindAt = picked);
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      context.showErrorSnackbar('Please add a title.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final reminder = await ref.read(
        createReminderProvider((
          reminderType: _reminderType,
          title: _titleController.text.trim(),
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          remindAt: _remindAt,
          recurrence: _isYearly ? 'yearly' : 'none',
          familyMemberId: null,
        )).future,
      );
      await _offerTimelineLink(reminder.id);
      if (!mounted) return;
      context.showSuccessSnackbar('Added to your calendar.');
      context.pop();
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not save that. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _offerTimelineLink(String reminderId) async {
    if (_reminderType != 'anniversary') return;
    final shouldLink = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to your Timeline too?'),
        content: const Text('This will also log it as a memory you can look back on.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add it'),
          ),
        ],
      ),
    );
    if (shouldLink != true || !mounted) return;

    final supabase = Supabase.instance.client;
    final relationshipId = await ref.read(currentRelationshipIdProvider.future);
    final userId = supabase.auth.currentUser?.id;
    if (relationshipId == null || userId == null) return;

    final timelineRepository = TimelineRepository(supabase);
    final event = await timelineRepository.createEvent(
      relationshipId: relationshipId,
      loggedBy: userId,
      eventType: 'anniversary',
      title: _titleController.text.trim(),
      occurredAt: _remindAt,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );
    await ref.read(remindersRepositoryProvider).linkReminderToTimelineEvent(
          reminderId: reminderId,
          timelineEventId: event.id,
        );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Add to calendar',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextFormField(
              controller: _titleController,
              label: 'Title',
              hintText: 'Our anniversary, Emma\'s birthday...',
            ),
            Gap(Spacing.md.h),
            AppTextFormField(
              controller: _noteController,
              label: 'Note (optional)',
              maxLines: 3,
              maxLength: 300,
            ),
            Gap(Spacing.md.h),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text('${_remindAt.year}-${_remindAt.month.toString().padLeft(2, '0')}-${_remindAt.day.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDate,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeats every year'),
              value: _isYearly,
              onChanged: (value) => setState(() => _isYearly = value),
            ),
            const Spacer(),
            AppButton(
              label: _isSaving ? 'Saving...' : 'Save',
              onPressed: _isSaving ? null : _save,
              size: ButtonSize.large,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}
