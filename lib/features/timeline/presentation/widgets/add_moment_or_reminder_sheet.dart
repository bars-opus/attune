// lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart

import 'package:attune/core/utils/exports/export_screens.dart';

enum AddChoice { moment, reminder }

/// The Timeline FAB's entry point — replaces what used to be two separate
/// FABs (Timeline's "log a moment", Calendar's "add reminder") with one
/// FAB and a choice between the two existing, unmodified flows.
class AddMomentOrReminderSheet {
  static Future<AddChoice?> show(BuildContext context) {
    return showModalBottomSheet<AddChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.md.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InfoRowWidget(
                  title: 'Log a moment',
                  subtitle: 'A milestone, conflict, highlight...',
                  icon: Icons.auto_awesome_outlined,
                  disableTrailing: true,
                  showAvatar: false,
                  showDivider: false,
                  showTrailingArrow: false,
                  onTap: () => Navigator.of(context).pop(AddChoice.moment),
                ),
                InfoRowWidget(
                  title: 'Add a reminder',
                  subtitle: 'Anniversary, birthday, or any date',
                  icon: Icons.event_outlined,
                  disableTrailing: true,
                  showAvatar: false,
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
