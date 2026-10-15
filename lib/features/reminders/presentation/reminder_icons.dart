import 'package:flutter/material.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart'
    show planningCategoryFill;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Every icon on a reminder's row fits its occasion: the coloured circle
/// shows it in outline, the end of the row shows it bolder.

/// The occasion in the coloured circle.
IconData reminderCircleIcon(String? type) => switch (type) {
  'birthday' => Icons.cake_outlined,
  'anniversary' => Icons.celebration_outlined,
  'checkin' => Icons.forum_outlined,
  'ai_generated' => Icons.auto_awesome_outlined,
  _ => Icons.notifications_none_rounded,
};

/// The occasion at the end of the row.
IconData reminderOccasionIcon(String? type) => switch (type) {
  'birthday' => FontAwesomeIcons.birthdayCake,
  'anniversary' => FontAwesomeIcons.champagneGlasses,
  'checkin' => FontAwesomeIcons.comments,
  'ai_generated' => FontAwesomeIcons.wandMagicSparkles,
  _ => FontAwesomeIcons.bell,
};

/// Each occasion's own colour, exactly as bright as Planning's category
/// icons in light and dark (planningCategoryFill): birthdays pink,
/// anniversaries gold, check-ins blue, suggestions purple, anything else
/// neutral.
Color reminderOccasionColor(String? type, BuildContext context) =>
    switch (type) {
      'birthday' => planningCategoryFill(context, 'pink'),
      'anniversary' => planningCategoryFill(context, 'amber'),
      'checkin' => planningCategoryFill(context, 'blue'),
      'ai_generated' => planningCategoryFill(context, 'purple'),
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };

/// The occasion in words, for screen readers.
String reminderOccasionLabel(String? type) => switch (type) {
  'birthday' => 'Birthday',
  'anniversary' => 'Anniversary',
  'checkin' => 'Check-in',
  'ai_generated' => 'Suggested',
  _ => 'Reminder',
};

/// The occasion icon as a row's trailing widget.
class ReminderOccasionIcon extends StatelessWidget {
  const ReminderOccasionIcon({super.key, required this.type});
  final String? type;

  @override
  Widget build(BuildContext context) => Semantics(
    label: reminderOccasionLabel(type),
    child: Icon(
      reminderOccasionIcon(type),
      size: 20,
      color: reminderOccasionColor(type, context),
    ),
  );
}
