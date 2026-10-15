import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_models.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';
import '../screens/planning_entry_screen.dart';

/// Opens a recent plan, its category's name ready to fly in.
void openPlanningRecent(
  BuildContext context,
  String relationshipId,
  PlanningRecentEntry recent,
) => Navigator.of(context).push(
  planningRoute(
    PlanningEntryScreen(
      relationshipId: relationshipId,
      entryId: recent.entry.id,
      categoryId: recent.categoryId,
      categoryName: recent.categoryName,
    ),
  ),
);

/// One recent plan: the title, then the category and when it was last
/// worked on.
class PlanningRecentRow extends StatelessWidget {
  const PlanningRecentRow({
    super.key,
    required this.recent,
    required this.now,
    required this.last,
    required this.onTap,
  });

  final PlanningRecentEntry recent;
  final DateTime now;

  /// The last row in its card: no divider under it.
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InfoRowWidget(
      // No leading icon: like a category's plans, the title and the line
      // under it carry the row.
      leadingWidget: const SizedBox.shrink(),
      avatarRadius: 0,
      iconSize: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      title: recent.entry.title,
      subtitle: MyDateFormat.join([
        recent.categoryName,
        planningRowDate(recent.entry.lastActivityAt, now),
      ]),
      titleMaxLines: 1,
      subTitleMaxLines: 1,
      showDivider: !last,
      disableTrailing: true,
      onTap: onTap,
    );
  }
}

/// The Planning home's Recent: the five plans worked on last, across every
/// category, in one card; See all when there are more. Nothing at all
/// while it loads, if it fails, or before there's anything to show — the
/// categories below never wait on it.
class PlanningRecentSection extends ConsumerWidget {
  const PlanningRecentSection({
    super.key,
    required this.relationshipId,
    required this.onSeeAll,
  });

  final String relationshipId;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(planningRecentProvider(relationshipId)).valueOrNull;
    if (page == null || page.entries.isEmpty) return const SizedBox.shrink();
    final shown = page.entries.take(planningRecentShown).toList();
    final more = page.entries.length > planningRecentShown || page.hasMore;
    final theme = Theme.of(context);
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  child: Text(
                    'Recent',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
              if (more)
                TextButton(onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
          if (!more) const Gap(Spacing.sm),
          CardInkWell(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++)
                  PlanningRecentRow(
                    recent: shown[i],
                    now: now,
                    last: i == shown.length - 1,
                    onTap:
                        () => openPlanningRecent(
                          context,
                          relationshipId,
                          shown[i],
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
