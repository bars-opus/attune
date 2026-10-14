import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/together_item.dart';

String togetherWhoLabel(TogetherWho who, String partnerName) => switch (who) {
  TogetherWho.me => 'You',
  TogetherWho.partner => partnerName,
  TogetherWho.us => 'Both of you',
};

/// One thing on the Agenda: what, when and whose, in the app's row style.
class TogetherItemRow extends StatelessWidget {
  const TogetherItemRow({
    super.key,
    required this.item,
    required this.me,
    required this.partnerName,
    this.last = false,
    this.lead,
    this.onTap,
  });

  final TogetherItem item;
  final String? me;
  final String partnerName;

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
        return switch (item.sourceRef['reminder_type']) {
          'birthday' => Icons.cake_outlined,
          'anniversary' => Icons.favorite_border_rounded,
          _ => Icons.notifications_none_rounded,
        };
      case TogetherItemKind.planningDate:
        return Icons.checklist_rounded;
      case TogetherItemKind.planningItem:
        return item.sourceRef['is_complete'] == true
            ? Icons.check_box_outlined
            : Icons.check_box_outline_blank_rounded;
      case TogetherItemKind.moment:
        return Icons.auto_awesome_outlined;
    }
  }

  String get _when {
    final s = item.startsAt;
    if (item.allDay || s == null) {
      return switch (item.kind) {
        TogetherItemKind.reminder => 'Reminder',
        TogetherItemKind.planningDate => 'Plan',
        TogetherItemKind.planningItem => 'To-do',
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
        togetherWhoLabel(who, partnerName),
    ];
    final done =
        item.kind == TogetherItemKind.planningItem &&
        item.sourceRef['is_complete'] == true;
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
      subtitle: parts.join(' · '),
      titleMaxLines: 1,
      subTitleMaxLines: 1,
      showDivider: !last,
      disableTrailing: true,
      onTap: _masked ? null : onTap,
    );
  }
}
