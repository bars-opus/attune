import 'package:attune/features/reminders/presentation/reminder_icons.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/together_item.dart';

String togetherWhoLabel(
  TogetherWho who,
  String partnerName, {
  String? coupleName,
}) => switch (who) {
  TogetherWho.me => 'You',
  TogetherWho.partner => partnerName,
  // The couple by the name they chose ("Couples" until they do).
  TogetherWho.us => coupleLabel(coupleName),
};

/// Lines for a Together row: one each normally; above 1.3x text, 2 title
/// lines and 3 subtitle lines so nothing is cut to "Dinner at the…" (Spec 5,
/// R5-13). Shared by agenda and ritual rows.
({int title, int subtitle}) togetherRowLines(BuildContext context) {
  final large = MediaQuery.textScalerOf(context).scale(10) / 10 > 1.3;
  return large ? (title: 2, subtitle: 3) : (title: 1, subtitle: 1);
}

/// One thing on the Agenda: what, when and whose, in the app's row style.
class TogetherItemRow extends StatelessWidget {
  const TogetherItemRow({
    super.key,
    required this.item,
    required this.me,
    required this.partnerName,
    this.coupleName,
    this.last = false,
    this.lead,
    this.onTap,
  });

  final TogetherItem item;
  final String? me;
  final String partnerName;

  /// The couple's chosen name, for things that are both of theirs.
  final String? coupleName;

  /// The last row in its card: no divider under it.
  final bool last;

  /// A leading phrase for the subtitle, e.g. "In 12 days".
  final String? lead;
  final VoidCallback? onTap;

  bool get _masked => item.isMaskedFor(me);

  IconData get _icon {
    if (_masked) return Icons.do_not_disturb_on_outlined;
    switch (item.kind) {
      case TogetherItemKind.event:
        return switch (item.sourceRef['kind']) {
          'trip' => Icons.flight_takeoff_rounded,
          'big_day' => Icons.star_outline_rounded,
          'ritual_occurrence' => Icons.event_repeat_rounded,
          _ => Icons.event_rounded,
        };
      case TogetherItemKind.reminder:
        // Its occasion, in the circle and again at the end of the row.
        return reminderCircleIcon(item.sourceRef['reminder_type'] as String?);
      case TogetherItemKind.planningDate:
        return Icons.checklist_rounded;
      case TogetherItemKind.planningItem:
        if (_isBill) return Icons.payments_outlined;
        return item.sourceRef['is_complete'] == true
            ? Icons.check_box_outlined
            : Icons.check_box_outline_blank_rounded;
      case TogetherItemKind.moment:
        return Icons.auto_awesome_outlined;
    }
  }

  /// A dated line from a plan's Expenses block: a bill, paid or not.
  bool get _isBill => item.sourceRef['block_type'] == 'expenses';

  String get _when {
    final s = item.startsAt;
    if (item.allDay || s == null) {
      return switch (item.kind) {
        TogetherItemKind.reminder => 'Reminder',
        TogetherItemKind.planningDate => 'Plan',
        TogetherItemKind.planningItem => _isBill ? 'Bill' : 'To-do',
        TogetherItemKind.moment => 'Moment',
        TogetherItemKind.event => 'All day',
      };
    }
    final e = item.endsAt;
    final t = DateFormat.jm();
    return e == null ? t.format(s) : '${t.format(s)} – ${t.format(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final who = me == null ? null : item.whoFor(me!);
    final whoColor = switch (who) {
      TogetherWho.me => colorScheme.tertiary,
      TogetherWho.partner => colorScheme.secondary,
      _ => colorScheme.primary,
    };
    final parts = [
      if (lead != null) lead!,
      _when,
      if (item.kind == TogetherItemKind.event && who != null && !_masked)
        togetherWhoLabel(who, partnerName, coupleName: coupleName),
    ];
    final done =
        item.kind == TogetherItemKind.planningItem &&
        item.sourceRef['is_complete'] == true;
    final lines = togetherRowLines(context);
    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      icon: _icon,
      iconColor: whoColor,
      backgroundColor: whoColor.withValues(alpha: 0.12),
      title: item.title.isEmpty ? 'Untitled' : item.title,
      titleStyle:
          done
              ? Theme.of(context).textTheme.titleSmall?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              )
              : null,
      subtitle: MyDateFormat.join(parts),
      titleMaxLines: lines.title,
      subTitleMaxLines: lines.subtitle,
      showDivider: !last,
      // A reminder ends with its occasion (cake, celebration, …).
      trailing:
          item.kind == TogetherItemKind.reminder
              ? ReminderOccasionIcon(
                type: item.sourceRef['reminder_type'] as String?,
              )
              : null,
      disableTrailing: item.kind != TogetherItemKind.reminder,
      onTap: _masked ? null : onTap,
    );
  }
}
