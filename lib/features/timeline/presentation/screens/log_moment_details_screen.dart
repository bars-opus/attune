// lib/features/timeline/presentation/screens/log_moment_details_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';


class LogMomentDetailsScreen extends ConsumerStatefulWidget {
  final String eventType;
  final String? editEventId;
  final Map<String, dynamic>? initialData;

  const LogMomentDetailsScreen({
    super.key,
    required this.eventType,
    this.editEventId,
    this.initialData,
  });

  @override
  ConsumerState<LogMomentDetailsScreen> createState() =>
      _LogMomentDetailsScreenState();
}

class _LogMomentDetailsScreenState
    extends ConsumerState<LogMomentDetailsScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  int? _moodScore;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _titleController.text = widget.initialData!['title'] ?? '';
      _noteController.text = widget.initialData!['note'] ?? '';
      _selectedDate = widget.initialData!['occurred_at'] ?? DateTime.now();
      _moodScore = widget.initialData!['mood_score'];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _getEventTypeDisplay() {
    switch (widget.eventType) {
      case 'milestone':
        return 'Milestone';
      case 'conflict':
        return 'Conflict';
      case 'highlight':
        return 'Highlight';
      case 'first':
        return 'First';
      case 'anniversary':
        return 'Anniversary';
      default:
        return widget.eventType;
    }
  }

  Color _getEventTypeColor() {
    switch (widget.eventType) {
      case 'milestone':
        return Theme.of(context).colorScheme.primary;
      case 'conflict':
        return Colors.red;
      case 'highlight':
        return Colors.amber;
      case 'first':
        return Colors.purple;
      case 'anniversary':
        return Colors.pink;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  bool get _isValid =>
      _titleController.text.trim().isNotEmpty && !_isSubmitting;

  Future<void> _saveMoment() async {
    if (!_isValid) return;

    setState(() => _isSubmitting = true);

    try {
      if (widget.editEventId != null) {
        // Update existing event
        await ref.read(
          updateTimelineEventProvider((
            eventId: widget.editEventId!,
            eventType: widget.eventType,
            title: _titleController.text.trim(),
            note:
                _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
            moodScore: _moodScore,
            occurredAt: _selectedDate,
          )).future,
        );
      } else {
        // Create new event
        await ref.read(
          createTimelineEventProvider((
            eventType: widget.eventType,
            title: _titleController.text.trim(),
            occurredAt: _selectedDate,
            note:
                _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
            moodScore: _moodScore,
          )).future,
        );
      }

      if (mounted) {
        Navigator.pop(context, true); // Return true to signal refresh needed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final eventColor = _getEventTypeColor();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.editEventId != null
              ? 'Edit ${_getEventTypeDisplay()}'
              : _getEventTypeDisplay(),
          style: textTheme.titleMedium,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title field
            Text(
              'Title *',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            AppTextFormField(
              controller: _titleController,
              hintText: _getTitleHint(),
              maxLength: 80,
              // buildCounter:
              //     (
              //       context, {
              //       required currentLength,
              //       required isFocused,
              //       maxLength,
              //     }) => null, 
                  
                  label: '',
            ),
            Gap(Spacing.lg.h),

            // Date picker
            Text(
              'Date',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: ListTile(
                title: Text(
                  _formatDate(_selectedDate),
                  style: textTheme.bodyLarge,
                ),
                trailing: const Icon(Icons.calendar_today, size: 20),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
              ),
            ),
            Gap(Spacing.lg.h),

            // Mood slider
            Text(
              'How did this feel? (optional)',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Row(
              children: [
                Text('1', style: textTheme.bodySmall),
                Expanded(
                  child: Slider(
                    value: (_moodScore ?? 5).toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    activeColor: eventColor,
                    onChanged:
                        (value) => setState(() => _moodScore = value.round()),
                  ),
                ),
                Text('10', style: textTheme.bodySmall),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Difficult', style: textTheme.bodySmall),
                Text('Amazing', style: textTheme.bodySmall),
              ],
            ),
            if (_moodScore != null)
              Padding(
                padding: EdgeInsets.only(top: Spacing.xs.h),
                child: Text(
                  'Selected: $_moodScore/10',
                  style: textTheme.bodySmall?.copyWith(color: eventColor),
                ),
              ),
            Gap(Spacing.lg.h),

            // Note field (optional)
            Text(
              'Add a note (optional)',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            AppTextFormField(
              controller: _noteController,
              hintText: 'What happened? How did it feel?',
              maxLines: 4,
              maxLength: 300,
              // buildCounter:
              //     (
              //       context, {
              //       required currentLength,
              //       required isFocused,
              //       maxLength,
              //     }) => null,
                   label: '',
            ),
            Gap(Spacing.xl.h),

            // Save button
            AppButton(
              label:
                  widget.editEventId != null ? 'Save changes' : 'Save moment',
              onPressed: _isValid ? _saveMoment : null,
              size: ButtonSize.large,
              width: double.infinity,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }

  String _getTitleHint() {
    switch (widget.eventType) {
      case 'milestone':
        return 'e.g., Got engaged, Moved in together';
      case 'conflict':
        return 'e.g., Fight about plans, Disagreement about money';
      case 'highlight':
        return 'e.g., Perfect date night, She made me laugh';
      case 'first':
        return 'e.g., First kiss, First trip together';
      case 'anniversary':
        return 'e.g., 1 year together, Dating anniversary';
      default:
        return 'Enter a title';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day} ${_getMonth(date.month)} ${date.year}';
  }

  String _getMonth(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
