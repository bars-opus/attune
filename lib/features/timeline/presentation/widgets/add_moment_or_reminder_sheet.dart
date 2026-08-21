// lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart

import 'package:attune/core/utils/exports/export_screens.dart';

enum AddChoice { moment, reminder }

/// The Timeline FAB's entry point — replaces what used to be two separate
/// FABs (Timeline's "log a moment", Calendar's "add reminder") with one
/// FAB and a choice between the two existing, unmodified flows.
class AddMomentOrReminderSheet {
  static Future<AddChoice?> show(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<AddChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(Spacing.md.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Gap(Spacing.md),
                InfoRowWidget(
                  title: 'Log a moment',
                  subtitle: 'A milestone, conflict, highlight...',
                  icon: Icons.auto_awesome_outlined,
                  showAvatar: false,
                  showDivider: false,
                  showTrailingArrow: false,
                  trailing: Icon(
                    Icons.add,
                    size: 25.h,
                    color: colorScheme.onBackground.withOpacity(.5),
                  ),
                  onTap: () => Navigator.of(context).pop(AddChoice.moment),
                ),
                AppDivider(),
                InfoRowWidget(
                  title: 'Add a reminder',
                  subtitle: 'Anniversary, birthday, or any date',
                  icon: Icons.event_outlined,
                  showAvatar: false,
                  trailing: Icon(
                    Icons.add,
                    size: 25.h,
                    color: colorScheme.onBackground.withOpacity(.5),
                  ),
                  showDivider: false,
                  showTrailingArrow: false,
                  onTap: () => Navigator.of(context).pop(AddChoice.reminder),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
