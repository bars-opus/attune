import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/core/notes/note_date_sections.dart';
import 'package:attune/core/notes/note_section.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../planning_providers.dart';
import '../planning_ui.dart';
import '../widgets/planning_recent.dart';
import '../widgets/planning_skeletons.dart';

/// Every recent plan across the couple's categories, most recently worked
/// on first, grouped like a category's plans (Today, Yesterday, Previous 7
/// Days…), each row naming its category. Loads more as it scrolls.
class PlanningRecentScreen extends ConsumerWidget {
  const PlanningRecentScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = planningRecentListProvider(relationshipId);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: false,
        title: Text(
          'Recent',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
      body: ref
          .watch(provider)
          .when(
            skipLoadingOnReload: true,
            loading: () => const PlanningEntriesSkeleton(),
            error:
                (e, _) => PlanningErrorState(
                  error: e,
                  onRetry: () => ref.invalidate(provider),
                ),
            data: (s) {
              final now = DateTime.now();
              final groups = noteDateSections(
                s.entries,
                (e) => e.entry.lastActivityAt,
                now,
              );
              return RefreshIndicator(
                onRefresh: () => ref.refresh(provider.future),
                child: NotificationListener<ScrollNotification>(
                  // Near the end, the next page.
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 400) {
                      ref.read(provider.notifier).loadMore();
                    }
                    return false;
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppContentWidth.padded(
                      context,
                      const EdgeInsets.only(bottom: Spacing.xl),
                    ),
                    children: [
                      for (final g in groups)
                        NoteSection(
                          title: g.title,
                          children: [
                            for (var i = 0; i < g.items.length; i++)
                              PlanningRecentRow(
                                recent: g.items[i],
                                now: now,
                                last: i == g.items.length - 1,
                                onTap:
                                    () => openPlanningRecent(
                                      context,
                                      relationshipId,
                                      g.items[i],
                                    ),
                              ),
                          ],
                        ),
                      if (s.loadingMore)
                        const Padding(
                          padding: EdgeInsets.all(Spacing.md),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}
