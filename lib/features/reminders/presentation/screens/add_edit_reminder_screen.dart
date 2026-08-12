// lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/timeline/data/repositories/timeline_repository.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddEditReminderScreen extends ConsumerStatefulWidget {
  const AddEditReminderScreen({super.key});

  @override
  ConsumerState<AddEditReminderScreen> createState() =>
      _AddEditReminderScreenState();
}

class _AddEditReminderScreenState extends ConsumerState<AddEditReminderScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  String _reminderType = 'anniversary';
  DateTime _remindAt = DateTime.now();
  bool _isYearly = true;
  bool _isSaving = false;

  // _remindAt always holds a real DateTime (defaults to now), so it alone
  // can't tell "no date chosen yet" apart from "user picked today" — this
  // flag tracks whether _pickDate has actually fired at least once, which
  // is what the Save button's visibility gates on.
  bool _dateSelected = false;

  bool get _canSave => _titleController.text.trim().isNotEmpty && _dateSelected;

  @override
  void initState() {
    super.initState();
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
          note:
              _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
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
            Row(
              children: [
                Expanded(
                  child: InfoRowWidget(
                    title: 'Add to calendar',
                    subtitle: '',
                    iconColor: colorScheme.onBackground,
                    icon: Icons.close,
                    showAvatar: false,
                    showTrailingArrow: true,
                    showDivider: false,
                    disableTrailing: true,
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
                ),
                if (_canSave)
                  ShakeTransition(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutBack,
                    child: AppButton(
                      elevation: 0,
                      animateButton: false,
                      label: 'Save',
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _save,
                      textColor: colorScheme.surface,
                      size: ButtonSize.large,
                      width: 100,
                      padding: Spacing.horizontalMd,
                      height: 30.h,
                      borderRadius: BorderRadius.circular(100.r),
                    ),
                  ),
              ],
            ),
            Gap(Spacing.lg.h),
            AppTextFormField(
              controller: _titleController,
              label: 'Title',
              hintText: 'Our anniversary, Emma\'s birthday...',
              autofocus: true,
            ),

            AppTextFormField(
              controller: _noteController,
              label: 'Note (optional)',
              maxLines: 3,
              maxLength: 300,
            ),
            Gap(Spacing.md),
            AppDivider(),
            InfoRowWidget(
              key: const Key('healingSelfReportDateRow'),
              subtitle: 'Date',
              title: DateFormat.yMMMd().format(_remindAt),
              icon: Icons.calendar_month,
              showDivider: false,
              avatarRadius: 25.h,
              onTap: _pickDate,
              disableTrailing: true,
              showAvatar: false,
              showTrailingArrow: false,
            ),
            AppDivider(),
            InfoRowWidget(
              title: 'Repeats every year',
              subtitle: '',
              icon: FontAwesomeIcons.repeat,
              showDivider: false,
              showAvatar: false,
              isToggleItem: true,
              toggleValue: _isYearly,
              onToggleChanged: (value) => setState(() => _isYearly = value),
            ),
            AppDivider(),

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
