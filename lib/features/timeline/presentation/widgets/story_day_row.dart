/// The calendar's third source (Plan C, Task 5; spec §5.3;
/// task-5-brief.md). Stories are never copied into `timeline_events` —
/// this row is composed at read time from [storyDayCountsProvider], the
/// same way [MomentsList]/[UpcomingRemindersSection] are composed
/// alongside events and reminders in `timeline_screen.dart` (spec §3.1).
///
/// **The one thing this widget must never do is filter by expiry.**
/// `storyDayCountsProvider`/`storyDayItemsProvider` already call
/// `list_story_day_counts`/`list_story_day_items`, which INCLUDE expired
/// items by contract (spec §5.5, `story_read_repository.dart`'s own
/// header) — that is the entire point of the feature (spec §1: "leaves
/// the reel... but stays in the couple's calendar forever"). This file
/// does no date arithmetic of its own and trusts the count/items the
/// provider returns exactly as given.
///
/// Tapping a day opens [StoryReelScreen.forDay] — the day-scoped mode
/// added by this task (see that file's header) rather than the
/// author-scoped mode Task 4 built, because a calendar day can hold
/// items from both partners and must show every non-deleted one,
/// expired or not.
library;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One row per calendar day that has at least one story
/// (`list_story_day_counts` omits days with zero, spec §5.5) —
/// [TimelineScreen] renders nothing at all for a day absent from that
/// list, the same "absence means don't draw" posture
/// `storyRingSummaryProvider` uses for authors with no active stories.
class StoryDayRow extends ConsumerWidget {
  const StoryDayRow({
    super.key,
    required this.relationshipId,
    required this.occurredOn,
    required this.itemCount,
  });

  final String relationshipId;
  final DateTime occurredOn;

  /// From `list_story_day_counts` — includes expired, non-deleted items
  /// only (a deleted item's `deleted_at` is not null, so it is excluded
  /// server-side from both this count and the day's items; spec §3.1/
  /// §3.2). This widget does not recompute the count from a separately
  /// fetched item list.
  final int itemCount;

  void _openDay(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StoryReelScreen.forDay(
          relationshipId: relationshipId,
          occurredOn: occurredOn,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = itemCount == 1 ? '1 story' : '$itemCount stories';

    return Semantics(
      button: true,
      label: 'Stories from this day, $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openDay(context),
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            // 44-48dp minimum tap target, matching the reel's own close/
            // delete affordances.
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps [StoryDayRow] with a loading/error/empty-safe read of
/// [storyDayCountsProvider] for exactly one day — [TimelineScreen] uses
/// this rather than watching the provider itself so its own build stays
/// unchanged for the loading/error branches it already has for events.
///
/// Renders nothing (not a spinner, not an error banner) while the count
/// is loading or fails: a day already shows only rows it has positive
/// data for (spec's own "date with stories shows a row"), so this
/// degrades the same way an empty result would rather than adding a new
/// visible failure mode to a date cell that otherwise only shows events/
/// reminders.
class StoryDayCountRow extends ConsumerWidget {
  const StoryDayCountRow({
    super.key,
    required this.relationshipId,
    required this.occurredOn,
  });

  final String relationshipId;
  final DateTime occurredOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthStart = DateTime(occurredOn.year, occurredOn.month, 1);
    final monthEnd = DateTime(occurredOn.year, occurredOn.month + 1, 0);
    final countsAsync = ref.watch(
      storyDayCountsProvider(
        StoryDayRangeKey(
          relationshipId: relationshipId,
          startOn: monthStart,
          endOn: monthEnd,
        ),
      ),
    );

    final counts = countsAsync.valueOrNull;
    if (counts == null) return const SizedBox.shrink();

    final match = counts.where((c) {
      final d = c.occurredOn;
      return d.year == occurredOn.year &&
          d.month == occurredOn.month &&
          d.day == occurredOn.day;
    }).toList();
    if (match.isEmpty || match.first.itemCount <= 0) {
      return const SizedBox.shrink();
    }

    return StoryDayRow(
      relationshipId: relationshipId,
      occurredOn: occurredOn,
      itemCount: match.first.itemCount,
    );
  }
}
