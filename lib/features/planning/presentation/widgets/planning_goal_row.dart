// lib/features/planning/presentation/widgets/planning_goal_row.dart
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';

import '../../data/models/planning_goal_model.dart';

/// One row on the Goals section of Planning home. Progress is shown as
/// "N of M" text plus a linear indicator, never a bare toggle — Goal
/// completion is derived from its children (spec §3.1), so this row
/// has no interactive completion control of its own; tapping it expands
/// to the child Task list, which is where completion actually happens.
class PlanningGoalRow extends StatelessWidget {
  const PlanningGoalRow({super.key, required this.goal, required this.onTap});

  final PlanningGoalModel goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InfoRowWidget(
      title: goal.title,
      subtitle: '${goal.completedChildCount} of ${goal.childCount} done',
      subTitleMaxLines: 1,
      showAvatar: false,
      onTap: onTap,
      showTrailingArrow: true,
      leadingWidget: goal.isComplete
          ? Icon(Icons.check_circle, color: colorScheme.primary)
          : SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: goal.progressFraction,
                strokeWidth: 3,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
    );
  }
}
