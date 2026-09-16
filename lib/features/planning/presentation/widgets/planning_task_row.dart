// lib/features/planning/presentation/widgets/planning_task_row.dart
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/planning_task_model.dart';

/// One row for a top-level Task, or a Goal's child Task inside its
/// expanded checklist. A real Checkbox, not InfoRowWidget's own toggle
/// (that renders a Switch, the wrong control for "mark this done").
class PlanningTaskRow extends StatelessWidget {
  const PlanningTaskRow({
    super.key,
    required this.task,
    required this.onToggleComplete,
    this.onTap,
  });

  final PlanningTaskModel task;
  final ValueChanged<bool> onToggleComplete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleParts = <String>[];
    if (task.dueDate != null) {
      subtitleParts.add(DateFormat('MMM d').format(task.dueDate!));
    }

    return InfoRowWidget(
      title: task.title,
      subtitle: subtitleParts.join(' · '),
      subTitleMaxLines: 1,
      showAvatar: false,
      onTap: onTap,
      titleStyle: task.isComplete
          ? TextStyle(
              decoration: TextDecoration.lineThrough,
              color: colorScheme.onSurfaceVariant,
            )
          : null,
      leadingWidget: Checkbox(
        value: task.isComplete,
        onChanged: (value) => onToggleComplete(value ?? false),
      ),
    );
  }
}
