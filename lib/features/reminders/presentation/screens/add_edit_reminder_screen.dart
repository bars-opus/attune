// lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart
import 'package:attune/core/providers/run_write.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show timelineRepositoryProvider, currentUserIdProvider;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Opens the reminder sheet: empty to add one, or with [reminder] to
/// edit or delete it.
Future<void> showReminderSheet(
  BuildContext context, {
  ReminderModel? reminder,
  DateTime? initialDate,
}) async {
  // Spec 1 W5 (§5.2): the anniversary reminder About us keeps opens its
  // own sheet ("This reminder follows About us"), not this form; from it,
  // "Reminder times and note" opens this form locked (final review I-2).
  if (reminder != null &&
      await showAboutUsReminderLink(
        context,
        reminderId: reminder.id,
        relationshipId: reminder.relationshipId,
        reminderType: reminder.reminderType,
        title: reminder.title,
        onReminderTimes:
            () => _openReminderForm(
              context,
              reminder: reminder,
              followsAboutUs: true,
            ),
      )) {
    return;
  }
  if (!context.mounted) return;
  await _openReminderForm(
    context,
    reminder: reminder,
    initialDate: initialDate,
  );
}

Future<void> _openReminderForm(
  BuildContext context, {
  ReminderModel? reminder,
  DateTime? initialDate,
  bool followsAboutUs = false,
}) async {
  if (!context.mounted) return;
  // The sheet closes with its confirmation; it is shown here, on the
  // screen behind, because the sheet's own messenger closes with it.
  final message = await BottomSheetUtils.showDocumentationBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.neutral,
    widget: AddEditReminderScreen(
      reminder: reminder,
      initialDate: initialDate,
      followsAboutUs: followsAboutUs,
    ),
  );
  if (message != null && context.mounted) {
    context.showSuccessSnackbar(message);
  }
}

class AddEditReminderScreen extends ConsumerStatefulWidget {
  const AddEditReminderScreen({
    super.key,
    this.reminder,
    this.initialDate,
    this.followsAboutUs = false,
  }) : assert(!followsAboutUs || reminder != null);

  /// The reminder being edited; null when adding one.
  final ReminderModel? reminder;

  /// The calendar day a new reminder is being added to: already chosen.
  final DateTime? initialDate;

  /// Spec 1 W5 final review I-2 (F-4 ruling): About us's anniversary
  /// reminder. Its date, title, type and repeat follow About us (plan P-6:
  /// the server's guard refuses them), so they are shown but can't change,
  /// and it can't be deleted here; its lead times and note stay the
  /// couple's and are all that is saved.
  final bool followsAboutUs;

  @override
  ConsumerState<AddEditReminderScreen> createState() =>
      _AddEditReminderScreenState();
}

class _AddEditReminderScreenState extends ConsumerState<AddEditReminderScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();

  /// None for a new reminder until the user picks one: a silent default
  /// filed birthdays as anniversaries.
  String? _reminderType;

  /// A stored type the picker doesn't offer (a check-in, a suggestion):
  /// saved back as it was unless the user picks another type.
  String? _keptType;

  DateTime _remindAt = DateTime.now();
  bool _isYearly = true;

  /// Once the user flips "Repeats every year" themselves, picking a type
  /// no longer sets it for them.
  bool _yearlyTouched = false;
  bool _isSaving = false;

  /// When the couple hears, in days before the date (0 = on the day).
  Set<int> _daysBefore = {0, 3};

  static const _leadTimes = {
    0: 'On the day',
    1: '1 day before',
    3: '3 days before',
    7: '1 week before',
  };

  // _remindAt always holds a real DateTime (defaults to now), so it alone
  // can't tell "no date chosen yet" apart from "user picked today" — this
  // flag tracks whether _pickDate has actually fired at least once, which
  // is what the Save button's visibility gates on.
  bool _dateSelected = false;

  /// The types the picker offers; any other stored type shows as Other.
  static const _pickerTypes = {'anniversary', 'birthday', 'custom'};

  bool get _isEditing => widget.reminder != null;

  bool get _locked => widget.followsAboutUs;

  @override
  void initState() {
    super.initState();
    final day = widget.initialDate;
    if (day != null) {
      _remindAt = DateTime(day.year, day.month, day.day);
      _dateSelected = true;
    }
    final r = widget.reminder;
    if (r != null) {
      _titleController.text = r.title;
      _noteController.text = r.note ?? '';
      _reminderType =
          _pickerTypes.contains(r.reminderType) ? r.reminderType : 'custom';
      if (!_pickerTypes.contains(r.reminderType)) _keptType = r.reminderType;
      _remindAt = r.remindAt;
      _isYearly = r.recurrence == 'yearly';
      _daysBefore = r.remindDaysBefore.toSet();
      _yearlyTouched = true; // an existing choice stands
      _dateSelected = true;
    }
    // Rebuilds the Save button's visibility as the user types — a plain
    // TextEditingController read doesn't trigger a rebuild on its own.
    _titleController.addListener(_handleTitleChanged);
  }

  void _handleTitleChanged() => setState(() {});

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() {
    // The picker opens on the date shown; leaving it there chooses it
    // (its wheel only reports changes, so today could never be picked).
    setState(() => _dateSelected = true);
    return showCupertinoDateTimeSheet(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: _remindAt,
      minimumDate: DateTime(1900),
      maximumDate: DateTime(2100),
      onChanged:
          (value) => setState(() {
            _remindAt = value;
            _dateSelected = true;
          }),
    );
  }

  Future<void> _save() async {
    // A second tap before the button rebuilds would save it twice.
    if (_isSaving) return;
    if (_locked) return _saveTimes();
    if (_titleController.text.trim().isEmpty) {
      context.showErrorSnackbar('Please add a title.');
      return;
    }
    if (_reminderType == null) {
      context.showErrorSnackbar('Choose what it’s for.');
      return;
    }
    if (!_dateSelected) {
      context.showErrorSnackbar('Pick a date.');
      return;
    }
    final now = DateTime.now();
    if (!_isYearly &&
        DateUtils.dateOnly(_remindAt).isBefore(DateUtils.dateOnly(now))) {
      // A one-off only goes off on its day, so a past one never would.
      context.showErrorSnackbar(
        'Pick today or a later date for a one-off reminder.',
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await runWrite(
          ref,
          updateReminderProvider((
            id: widget.reminder!.id,
            reminderType: _keptType ?? _reminderType!,
            title: _titleController.text.trim(),
            note:
                _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
            remindAt: _remindAt,
            recurrence: _isYearly ? 'yearly' : 'none',
            remindDaysBefore: _daysBefore.toList()..sort(),
          )),
        );
        if (!mounted) return;
        Navigator.of(context).pop('Saved.');
        return;
      }
      final reminder = await runWrite(
        ref,
        createReminderProvider((
          reminderType: _reminderType!,
          title: _titleController.text.trim(),
          note:
              _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
          remindAt: _remindAt,
          recurrence: _isYearly ? 'yearly' : 'none',
          remindDaysBefore: _daysBefore.toList()..sort(),
          familyMemberId: null,
        )),
      );
      // The reminder is saved: from here the sheet closes whatever happens,
      // so a failed Timeline copy can't lead to saving the reminder twice.
      var message = 'Reminder added.';
      try {
        await _offerTimelineLink(reminder.id);
      } catch (_) {
        message = "Reminder added. It couldn't be added to your Timeline.";
      }
      if (!mounted) return;
      Navigator.of(context).pop(message);
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not save that. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// The locked form's save (W5 final review I-2): the lead times and the
  /// note only.
  Future<void> _saveTimes() async {
    setState(() => _isSaving = true);
    try {
      final note = _noteController.text.trim();
      await runWrite(
        ref,
        updateReminderTimesProvider((
          id: widget.reminder!.id,
          note: note.isEmpty ? null : note,
          remindDaysBefore: _daysBefore.toList()..sort(),
        )),
      );
      if (!mounted) return;
      Navigator.of(context).pop('Saved.');
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not save that. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Delete this reminder?'),
            content: const Text('It will be removed for both of you.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await runWrite(ref, deleteReminderProvider(widget.reminder!.id));
      if (!mounted) return;
      // The memory it was made with (or made from) stays: it's the
      // couple's, not the reminder's.
      Navigator.of(context).pop(
        widget.reminder!.linkedTimelineEventId == null
            ? 'Reminder deleted.'
            : 'Reminder deleted. The memory stays on your Timeline.',
      );
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not delete that. Please try again.');
    }
  }

  Future<void> _offerTimelineLink(String reminderId) async {
    if (_reminderType != 'anniversary') return;
    final shouldLink = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add to your Timeline too?'),
            content: const Text(
              'This will also log it as a memory you can look back on.',
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
    if (shouldLink != true || !mounted) return;

    final relationshipId = await ref.read(currentRelationshipIdProvider.future);
    final userId = ref.read(currentUserIdProvider);
    if (relationshipId == null || userId == null) return;

    final event = await ref
        .read(timelineRepositoryProvider)
        .createEvent(
          relationshipId: relationshipId,
          loggedBy: userId,
          eventType: 'anniversary',
          title: _titleController.text.trim(),
          occurredAt: _remindAt,
          note:
              _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
        );
    await ref
        .read(remindersRepositoryProvider)
        .linkReminderToTimelineEvent(
          reminderId: reminderId,
          timelineEventId: event.id,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: ListView(
          children: [
            // The app's sheet header, Save as its text button. Always
            // wired: with no handler the header's button closes the sheet,
            // which would throw away what was typed; Save says what's
            // missing instead.
            BottomSheetHeader(
              title: _isEditing ? 'Edit reminder' : 'Add reminder',
              actionLabel: 'Save',
              onPressed: _isSaving ? () {} : _save,
            ),
            AppDivider(),
            if (_locked)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  Spacing.md.w,
                  Spacing.md,
                  Spacing.md.w,
                  0,
                ),
                child: Text(
                  AppLocalizations.of(context)!.aboutUs_reminderLocked,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Gap(Spacing.lg.h),
            AppTextFormField(
              controller: _titleController,
              label: 'Title',
              hintText: 'Our anniversary, Emma\'s birthday...',
              autofocus: !_locked,
              readOnly: _locked,
              maxLength: 80, // the database's limit
            ),

            AppTextFormField(
              controller: _noteController,
              label: 'Note (optional)',
              maxLines: 3,
              maxLength: 300,
            ),
            Gap(Spacing.md),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  // One line each, however narrow the screen.
                  ButtonSegment(
                    value: 'anniversary',
                    label: Text(
                      'Anniversary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: 'birthday',
                    label: Text(
                      'Birthday',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: 'custom',
                    label: Text(
                      'Other',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                emptySelectionAllowed: true,
                selected: {if (_reminderType != null) _reminderType!},
                onSelectionChanged:
                    _locked
                        ? null
                        : (s) => setState(() {
                          if (s.isEmpty) return;
                          _reminderType = s.first;
                          _keptType = null;
                          // Birthdays and anniversaries come round every
                          // year; anything else is a one-off by default.
                          if (!_yearlyTouched) {
                            _isYearly = s.first != 'custom';
                          }
                        }),
              ),
            ),
            Gap(Spacing.md),
            AppDivider(),
            InfoRowWidget(
              key: const Key('healingSelfReportDateRow'),
              subtitle: 'Date',
              title: MyDateFormat.toDate(_remindAt),
              icon: Icons.calendar_month,
              showDivider: true,
              avatarRadius: 25.h,
              // W5 final review I-2: About us's date, never changed here.
              onTap: _locked ? null : _pickDate,
              disableTrailing: true,
              showAvatar: false,
              showTrailingArrow: false,
            ),
            if (!_locked)
              InfoRowWidget(
                title: 'Repeats every year',
                subtitle: '',
                icon: FontAwesomeIcons.repeat,
                showDivider: true,
                showAvatar: false,
                isToggleItem: true,
                toggleValue: _isYearly,
                onToggleChanged:
                    (value) => setState(() {
                      _isYearly = value;
                      _yearlyTouched = true;
                    }),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.md.w,
                Spacing.md,
                Spacing.md.w,
                0,
              ),
              child: Text(
                'Remind us',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Padding(
              padding: Spacing.allMd,
              child: Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (final entry in _leadTimes.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: _daysBefore.contains(entry.key),
                      // The last one stays: a reminder has to go off.
                      onSelected:
                          (on) => setState(() {
                            if (on) {
                              _daysBefore.add(entry.key);
                            } else if (_daysBefore.length > 1) {
                              _daysBefore.remove(entry.key);
                            }
                          }),
                    ),
                ],
              ),
            ),
            AppDivider(),
            if (_isEditing && !_locked) ...[
              InfoRowWidget(
                title: 'Delete reminder',
                subtitle: '',
                icon: Icons.delete_outline_rounded,
                iconColor: colorScheme.error,
                showAvatar: false,
                showDivider: true,
                disableTrailing: true,
                onTap: _delete,
              ),
            ],

            //  AppButton(
            //         elevation: 0,
            //         label_isSaving ? 'Saving...' : 'Save',
            //         onPressed: onAgree,
            //         textColor: colorScheme.surface,
            //         size: ButtonSize.small,
            //         width: double.infinity,
            //         padding: Spacing.horizontalMd,
            //         height: 40.h,
            //       ),
            // AppButton(
            //   label: _isSaving ? 'Saving...' : 'Save',
            //   onPressed: _isSaving ? null : _save,
            //   size: ButtonSize.large,
            //   width: double.infinity,
            // ),
          ],
        ),
      ),
    );
  }
}
