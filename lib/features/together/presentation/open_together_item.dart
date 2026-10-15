import 'package:attune/features/planning/presentation/planning_ui.dart'
    show planningRoute;
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/together_item.dart';
import 'widgets/couple_event_sheet.dart';

/// Opens a Together item where it's edited: an event in its sheet, a
/// Planning date or to-do in its plan, a reminder in its sheet. A moment
/// has no editor here; [onMoment] decides (Together shows the month).
/// Shared by the Together hub and the Conversations screen's Upcoming.
Future<void> openTogetherItem(
  BuildContext context,
  TogetherItem item,
  String relationshipId, {
  VoidCallback? onMoment,
}) async {
  switch (item.kind) {
    case TogetherItemKind.event:
      await showCoupleEventSheet(
        context,
        relationshipId: relationshipId,
        item: item,
      );
    case TogetherItemKind.planningDate:
    case TogetherItemKind.planningItem:
      final entryId = item.sourceRef['entry_id'] as String?;
      if (entryId == null) return;
      await Navigator.of(context).push(
        planningRoute(
          PlanningEntryScreen(relationshipId: relationshipId, entryId: entryId),
        ),
      );
    case TogetherItemKind.reminder:
      // The reminder list may not be loaded yet on the first tap: wait.
      final reminders = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(remindersListProvider.future);
      if (!context.mounted) return;
      for (final r in reminders) {
        if (r.id == item.id) {
          await showReminderSheet(context, reminder: r);
          return;
        }
      }
    case TogetherItemKind.moment:
      onMoment?.call();
  }
}
