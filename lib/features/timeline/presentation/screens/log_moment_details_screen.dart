// lib/features/timeline/presentation/screens/log_moment_details_screen.dart
import 'package:attune/core/providers/run_write.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

/// Log a moment in one sheet: the kind of moment is picked at the top,
/// then the details. With [day], it starts on that date. True once saved.
///
/// To edit, pass the moment's [eventType], [editEventId] and [initialData].
Future<bool?> showMomentSheet(
  BuildContext context, {
  DateTime? day,
  String? eventType,
  String? editEventId,
  Map<String, dynamic>? initialData,
}) => BottomSheetUtils.showDocumentationBottomSheet<bool>(
  context: context,
  backgroundColor: Theme.of(context).colorScheme.neutral,
  widget: LogMomentDetailsScreen(
    eventType: eventType,
    editEventId: editEventId,
    initialData: initialData ?? (day == null ? null : {'occurred_at': day}),
    inSheet: true,
  ),
);

class LogMomentDetailsScreen extends ConsumerStatefulWidget {
  /// Null: the kind is chosen on this screen.
  final String? eventType;
  final String? editEventId;
  final Map<String, dynamic>? initialData;

  const LogMomentDetailsScreen({
    super.key,
    required this.eventType,
    this.editEventId,
    this.initialData,
    this.inSheet = false,
  });

  /// Shown as a sheet ([showMomentSheet]) rather than on its own route.
  final bool inSheet;

  /// Only anniversary and milestone moments read as something worth
  /// re-celebrating on a fixed yearly date — conflict/highlight/first
  /// don't fit a recurring nudge the same way.
  bool get isEligibleForReminderOffer => _offersReminder(eventType);

  static bool _offersReminder(String? type) =>
      type == 'anniversary' || type == 'milestone';

  @override
  ConsumerState<LogMomentDetailsScreen> createState() =>
      _LogMomentDetailsScreenState();
}

class _LogMomentDetailsScreenState
    extends ConsumerState<LogMomentDetailsScreen> {
  static const String _reminderErrorMessage =
      "Couldn't add that reminder — try again from Calendar.";

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  int? _moodScore;
  bool _isSubmitting = false;

  /// A conflict kept off the partner's timeline (Together Phase 4 R7).
  bool _private = false;

  /// The kind of moment: given, or picked here.
  late String? _type = widget.eventType;

  static const _types = [
    'milestone',
    'highlight',
    'conflict',
    'first',
    'anniversary',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _titleController.text = widget.initialData!['title'] ?? '';
      _noteController.text = widget.initialData!['note'] ?? '';
      _selectedDate = widget.initialData!['occurred_at'] ?? DateTime.now();
      _moodScore = widget.initialData!['mood_score'];
      _private = widget.initialData!['visibility'] == 'private';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _getEventTypeDisplay() {
    switch (_type) {
      case null:
        return 'Log a moment';
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
        return _type!;
    }
  }

  Color _getEventTypeColor() {
    switch (_type) {
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

  /// Only conflicts carry a visibility choice; others stay as they are.
  String? get _visibility =>
      _type == 'conflict' ? (_private ? 'private' : 'shared') : null;

  Future<void> _saveMoment() async {
    if (_isSubmitting) return;
    if (_type == null) {
      context.showErrorSnackbar('Choose what kind of moment it is.');
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      context.showErrorSnackbar('Give it a title.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (widget.editEventId != null) {
        // Update existing event
        await runWrite(
          ref,
          updateTimelineEventProvider((
            eventId: widget.editEventId!,
            eventType: _type,
            title: _titleController.text.trim(),
            note:
                _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
            clearNote: _noteController.text.trim().isEmpty,
            moodScore: _moodScore,
            occurredAt: _selectedDate,
            visibility: _visibility,
          )),
        );
      } else {
        // Create new event
        final createdEvent = await runWrite(
          ref,
          createTimelineEventProvider((
            eventType: _type!,
            title: _titleController.text.trim(),
            occurredAt: _selectedDate,
            note:
                _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
            moodScore: _moodScore,
            visibility: _visibility ?? 'shared',
          )),
        );

        if (LogMomentDetailsScreen._offersReminder(_type) && mounted) {
          await _offerYearlyReminder(createdEvent);
        }
      }

      if (mounted) {
        Navigator.pop(context, true); // Return true to signal refresh needed
      }
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar(
          "Couldn't save that moment. Please try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _offerYearlyReminder(TimelineEventModel createdEvent) async {
    final shouldAdd = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Remind us to revisit this next year?'),
            content: const Text(
              "We'll nudge you both around this date each year.",
            ),
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
    if (shouldAdd != true || !mounted) return;

    ReminderModel reminder;
    try {
      reminder = await runWrite(
        ref,
        createReminderProvider((
          reminderType: 'anniversary',
          title: createdEvent.title,
          note: null,
          remindAt: createdEvent.occurredAt,
          recurrence: 'yearly',
          familyMemberId: null,
          remindDaysBefore: const [0, 3],
        )),
      );
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar(_reminderErrorMessage);
      return;
    }

    try {
      await ref
          .read(remindersRepositoryProvider)
          .linkReminderToTimelineEvent(
            reminderId: reminder.id,
            timelineEventId: createdEvent.id,
          );
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar(_reminderErrorMessage);
    }
  }

  /// The app's date wheel, as the other sheets use: from 1950 (couples
  /// log moments from long before the app) to today, or the moment's own
  /// date if it sits ahead (a memory that follows its reminder can).
  Future<void> _pickDate() {
    final now = DateTime.now();
    return showCupertinoDateTimeSheet(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: _selectedDate,
      minimumDate: DateTime(1950),
      maximumDate: _selectedDate.isAfter(now) ? _selectedDate : now,
      sheetHeight: 350.h,
      onChanged: (d) => setState(() => _selectedDate = DateUtils.dateOnly(d)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final eventColor = _getEventTypeColor();
    final label = textTheme.labelLarge;

    // Laid out like the app's other sheets (a note's add sheets, the
    // reminder sheet): the header with Save, fields, rows with dividers.
    return Scaffold(
      // On its own route (Pulse's way in) there's only the way back above.
      appBar: widget.inSheet ? null : AppBar(),
      body: ListView(
        children: [
          BottomSheetHeader(
            title:
                widget.editEventId != null
                    ? 'Edit ${_getEventTypeDisplay()}'
                    : _getEventTypeDisplay(),
            actionLabel: 'Save',
            // Always wired: with no handler the header's button closes the
            // sheet, which would throw away what was typed.
            onPressed: _isSubmitting ? () {} : _saveMoment,
          ),
          AppDivider(),
          // The kind, when it's chosen here: a plain radio list, styled
          // like the app's other radio rows (Together settings).
          if (widget.eventType == null) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.md.w,
                Spacing.md,
                Spacing.md.w,
                0,
              ),
              child: Text('What kind of moment?', style: label),
            ),
            for (final type in _types)
              RadioListTile<String>(
                value: type,
                groupValue: _type,
                title: Text(
                  calendarEventTypeLabel(type),
                  style: textTheme.titleSmall?.copyWith(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                onChanged: (v) => setState(() => _type = v),
              ),
            AppDivider(),
          ],
          AppTextFormField(
            controller: _titleController,
            label: 'Title',
            hintText: _getTitleHint(),
            maxLength: 80,
            // The title hint and Save read the field: keep them current.
            onChanged: (_) => setState(() {}),
          ),
          AppTextFormField(
            controller: _noteController,
            label: 'Note (optional)',
            hintText: 'What happened? How did it feel?',
            maxLines: 3,
            maxLength: 300,
          ),
          Gap(Spacing.md),
          AppDivider(),
          InfoRowWidget(
            key: const Key('momentDateRow'),
            subtitle: 'Date',
            title: MyDateFormat.toDate(_selectedDate),
            icon: Icons.calendar_month,
            showDivider: true,
            showAvatar: false,
            showTrailingArrow: false,
            disableTrailing: true,
            onTap: _pickDate,
          ),
          if (_type == 'conflict')
            InfoRowWidget(
              title: 'Just for me',
              subtitle:
                  "Kept off your partner's timeline. It still helps you look back.",
              icon: Icons.lock_outline_rounded,
              showAvatar: false,
              showDivider: true,
              isToggleItem: true,
              toggleValue: _private,
              onToggleChanged: (v) => setState(() => _private = v),
            ),
          // How it felt (optional).
          Padding(
            padding: Spacing.allMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How did this feel? (optional)', style: label),
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
                            (value) =>
                                setState(() => _moodScore = value.round()),
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
              ],
            ),
          ),
          Gap(Spacing.xl.h),
        ],
      ),
    );
  }

  String _getTitleHint() {
    switch (_type) {
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
}
