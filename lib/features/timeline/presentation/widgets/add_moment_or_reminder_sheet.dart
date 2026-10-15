// lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_details_screen.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/couple_event_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AddChoice { event, moment, reminder }

/// What can be added on [day]: a plan from today on, a moment up to today,
/// a reminder on any day. With no day (the + button), all three.
Set<AddChoice> addChoicesFor(DateTime? day, {DateTime? now}) {
  if (day == null) return AddChoice.values.toSet();
  final t = now ?? DateTime.now();
  final today = DateTime(t.year, t.month, t.day);
  final d = DateTime(day.year, day.month, day.day);
  return {
    if (!d.isBefore(today)) AddChoice.event,
    if (!d.isAfter(today)) AddChoice.moment,
    AddChoice.reminder,
  };
}

/// The one way in to adding something to the calendar — the Together and
/// Month + buttons, and a day's "Add to this day" — so each flow opens,
/// refreshes and confirms the same way wherever it starts. With [day], the
/// flows start on that date.
Future<void> openAddFlow(
  BuildContext context, {
  required String relationshipId,
  DateTime? day,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final choice = await AddMomentOrReminderSheet.show(context, day: day);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case AddChoice.event:
      // The event sheet refreshes the calendar and confirms itself.
      await showCoupleEventSheet(
        context,
        relationshipId: relationshipId,
        day: day,
      );
    case AddChoice.moment:
      final saved = await showMomentSheet(context, day: day);
      if (saved == true && context.mounted) {
        context.showSuccessSnackbar('Moment saved.');
      }
    case AddChoice.reminder:
      await showReminderSheet(context, initialDate: day);
      container.invalidate(remindersListProvider);
  }
  // Refetch now rather than waiting on the live signal, which can lag or
  // drop (the moment's own month was refreshed when it saved).
  if (choice != AddChoice.event) container.invalidate(togetherRangeProvider);
}

/// The chooser: plan something, log a moment, add a reminder — only the
/// ones that fit [day], under its date.
class AddMomentOrReminderSheet {
  static Future<AddChoice?> show(BuildContext context, {DateTime? day}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final choices = addChoicesFor(day);
    final options = [
      if (choices.contains(AddChoice.event))
        (
          AddChoice.event,
          'Plan something together',
          'A date, a trip, anything with a time',
          Icons.event_rounded,
        ),
      if (choices.contains(AddChoice.moment))
        (
          AddChoice.moment,
          'Log a moment',
          'A milestone, conflict, highlight...',
          Icons.auto_awesome_outlined,
        ),
      if (choices.contains(AddChoice.reminder))
        (
          AddChoice.reminder,
          'Add a reminder',
          'Anniversary, birthday, or any date',
          Icons.notifications_none_rounded,
        ),
    ];
    return showModalBottomSheet<AddChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(Spacing.md.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Gap(Spacing.md),
                if (day != null) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                    child: Text(
                      'Add to ${MyDateFormat.toDate(day)}',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Gap(Spacing.sm),
                ],
                for (final (i, (value, title, subtitle, icon))
                    in options.indexed) ...[
                  if (i > 0) AppDivider(),
                  InfoRowWidget(
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    showAvatar: false,
                    showDivider: false,
                    showTrailingArrow: false,
                    trailing: Icon(
                      Icons.add,
                      size: 25.h,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    onTap: () => Navigator.of(context).pop(value),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
