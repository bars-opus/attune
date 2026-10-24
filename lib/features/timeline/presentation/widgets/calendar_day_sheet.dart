/// The modal bottom sheet a calendar date opens: that day's stories as a
/// tappable thumbnail row, plus the day's logged moments and anything
/// scheduled on it.
///
/// Replaces the previous inline "selected day" section for everything
/// that already happened — the inline section below the calendar now
/// carries UPCOMING items only. Tapping a date is the way to look at a
/// past day.
///
/// Like every other stories read path, this filters nothing by expiry:
/// `list_story_day_items` includes expired items by contract, which is
/// the whole point of expiry hiding an item from the reel rather than
/// removing it from the calendar (stories spec §1, §3.2).
library;

import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/couple_event_sheet.dart';
import 'package:attune/features/stories/data/story_read_repository.dart'
    show StoryDayCount;
import 'package:attune/features/stories/domain/story_day_rings.dart';
import 'package:attune/features/stories/domain/story_ring_copy.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/timeline/presentation/widgets/upcoming_reminders_section.dart';
import 'package:attune/features/together/presentation/widgets/together_item_row.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;

/// Opens the day sheet for [date].
Future<void> showCalendarDaySheet({
  required BuildContext context,
  required String? relationshipId,
  required DateTime date,
  required List<TimelineEventModel> events,
  required List<dynamic> reminders,
  required List<dynamic> planningEntries,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (sheetContext) => CalendarDaySheet(
          relationshipId: relationshipId,
          date: date,
          events: events,
          reminders: reminders,
          planningEntries: planningEntries,
          // The day closes first, so what's added shows on the calendar
          // rather than under a sheet that won't update.
          onAdd:
              relationshipId == null
                  ? null
                  : () {
                    Navigator.of(sheetContext).pop();
                    openAddFlow(
                      context,
                      relationshipId: relationshipId,
                      day: date,
                    );
                  },
        ),
  );
}

class CalendarDaySheet extends ConsumerWidget {
  const CalendarDaySheet({
    super.key,
    required this.relationshipId,
    required this.date,
    required this.events,
    required this.reminders,
    required this.planningEntries,
    this.onAdd,
  });

  final String? relationshipId;
  final DateTime date;
  final List<TimelineEventModel> events;
  final List<dynamic> reminders;
  final List<dynamic> planningEntries;

  /// "Add to this day"; hidden when null.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    // Only a day with Together events needs to know who is looking.
    final me =
        planningEntries.any((e) => e is TogetherItem)
            ? ref.watch(togetherMeProvider)
            : null;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          // Always the full width: while a day's stories are still loading
          // there's only short text here, and the sheet would otherwise
          // shrink around it until the stories arrive.
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        MyDateFormat.toDate(date),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (onAdd != null)
                      IconButton(
                        icon: const Icon(Icons.add_rounded),
                        tooltip: 'Add to this day',
                        onPressed: onAdd,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (relationshipId != null)
                  _StoriesSection(relationshipId: relationshipId!, date: date),
                if (events.isNotEmpty) ...[
                  Text('Moments', style: textTheme.labelLarge),
                  const SizedBox(height: 8),
                  for (final event in events)
                    _EventTile(event: event, colorScheme: colorScheme),
                  const SizedBox(height: 16),
                ],
                if (reminders.isNotEmpty || planningEntries.isNotEmpty) ...[
                  Text('Scheduled', style: textTheme.labelLarge),
                  const SizedBox(height: 8),
                  for (final (i, entry)
                      in [...reminders, ...planningEntries].indexed)
                    _ScheduledTile(
                      entry: entry,
                      relationshipId: relationshipId,
                      me: me,
                      last: i == reminders.length + planningEntries.length - 1,
                    ),
                ],
                if (events.isEmpty &&
                    reminders.isEmpty &&
                    planningEntries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No moments or plans on this day.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The day's stories as one ring per author, matching the Conversations
/// rings, each opening that author's own stories (04 #4). Counts come from
/// the whole day (`list_story_day_counts`), not the first page; expired
/// stories are included (spec §1/§3.2). A failed read says so, with Retry
/// (04 #5); a read in flight holds the place.
class _StoriesSection extends ConsumerWidget {
  const _StoriesSection({required this.relationshipId, required this.date});

  final String relationshipId;
  final DateTime date;

  void _openReel(BuildContext context, String authorId) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => StoryReelScreen.forDay(
              relationshipId: relationshipId,
              occurredOn: date,
              dayAuthorId: authorId,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final myId = ref.watch(currentUserProvider)?.id;
    // Watched from the first frame, so the partner's real name is ready
    // when the rings land (as on the Conversations rings).
    final partnerName =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull;
    final dayKey = StoryDayKey(
      relationshipId: relationshipId,
      occurredOn: date,
    );
    final monthKey = StoryDayRangeKey.month(
      relationshipId: relationshipId,
      day: date,
    );
    final itemsAsync = ref.watch(storyDayItemsProvider(dayKey));
    final countsAsync = ref.watch(storyDayCountsProvider(monthKey));
    final day = storyDayAuthorRings(
      day: date,
      counts: countsAsync.valueOrNull,
      items: itemsAsync.valueOrNull,
      myId: myId,
    );

    // The month's counts are usually cached by the grid. From a Wave 5
    // server they carry the partner's unviewed count, so the rings draw
    // right without the day's items. An older server's do not: until the
    // items first land, hold the place rather than draw the ring all-seen,
    // then bright (fix round 1, M-3). A failed items read falls through to
    // the counts. The day's items are still read with Wave 5 counts: on a
    // day of 50 stories or fewer they are the fresher read and win over a
    // month cached before a view (storyDayAuthorRings).
    final countsKnowUnviewed =
        day.rings.isNotEmpty &&
        (countsAsync.valueOrNull ?? const <StoryDayCount>[])
            .where(
              (c) =>
                  c.occurredOn.year == date.year &&
                  c.occurredOn.month == date.month &&
                  c.occurredOn.day == date.day &&
                  c.authorId != myId,
            )
            .every((c) => c.unviewedCount != null);
    if (!itemsAsync.hasValue && !itemsAsync.hasError && !countsKnowUnviewed) {
      return const _StoriesLoading();
    }

    if (day.rings.isEmpty) {
      final known = countsAsync.hasValue || itemsAsync.hasValue;
      if (known) return const SizedBox.shrink();
      if (countsAsync.isLoading || itemsAsync.isLoading) {
        return const _StoriesLoading();
      }
      return _StoriesLoadError(
        onRetry: () {
          ref.invalidate(storyDayCountsProvider(monthKey));
          unawaited(ref.read(storyDayItemsProvider(dayKey).notifier).refresh());
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          day.total == 1 ? '1 story' : '${day.total} stories',
          style: textTheme.labelLarge,
        ),
        const SizedBox(height: Spacing.sm),
        SizedBox(
          height: kStoryRingOuterDiameter + 4,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: day.rings.length,
            separatorBuilder: (_, __) => const SizedBox(width: Spacing.md),
            itemBuilder: (_, index) {
              final ring = day.rings[index];
              return _AuthorDayRing(
                key: ValueKey('day-story-ring-${ring.authorId}'),
                ring: ring,
                isMine: ring.authorId == myId,
                partnerName: partnerName,
                onTap: () => _openReel(context, ring.authorId),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// One author's ring for one calendar day.
class _AuthorDayRing extends ConsumerWidget {
  const _AuthorDayRing({
    super.key,
    required this.ring,
    required this.isMine,
    required this.partnerName,
    required this.onTap,
  });

  final StoryDayAuthorRing ring;
  final bool isMine;
  final String? partnerName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ring.thumbnailKey;
    final url =
        key == null
            ? null
            : ref.watch(storyMediaSignedUrlProvider(key)).valueOrNull;
    return StoryRing(
      isMine: isMine,
      hasStories: true,
      // No + on a past day: a capture posts to today.
      showPlusBadge: false,
      segmentCount: ring.count,
      unviewedCount: ring.unviewed,
      thumbnailUrl: url,
      thumbnailCacheKey: key,
      onTap: onTap,
      semanticLabel: storyDayRingLabel(
        mine: isMine,
        count: ring.count,
        partnerName: partnerName,
      ),
    );
  }
}

/// A read in flight: one neutral ring in the place the rings will take.
class _StoriesLoading extends StatelessWidget {
  const _StoriesLoading();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Loading stories',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            width: kStoryRingOuterDiameter,
            height: kStoryRingOuterDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      ),
    );
  }
}

/// The day's stories could not be read (04 #5): say so, offer Retry.
class _StoriesLoadError extends StatelessWidget {
  const _StoriesLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline_rounded,
                size: IconSizes.sm,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text(
                "Couldn't load this day's stories.",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.colorScheme});

  final TimelineEventModel event;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = calendarEventTypeColor(event.eventType, colorScheme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            alignment: Alignment.center,
            child: Icon(
              calendarEventTypeIcon(event.eventType),
              size: 12,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: textTheme.bodyMedium),
                if (event.note != null && event.note!.isNotEmpty)
                  Text(
                    event.note!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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

class _ScheduledTile extends ConsumerWidget {
  const _ScheduledTile({
    required this.entry,
    required this.relationshipId,
    this.me,
    this.last = false,
  });

  final Object entry;
  final String? relationshipId;

  /// The last row: no divider under it.
  final bool last;

  /// The viewer, so a partner's busy block stays closed.
  final String? me;

  /// A Planning row opens its plan; a reminder or Together event opens its editor.
  VoidCallback? _onTap(BuildContext context) => switch (entry) {
    PlanningCalendarEntry(:final entryId) when relationshipId != null => () {
      final navigator = Navigator.of(context);
      navigator.pop(); // close the day sheet first
      navigator.push(
        planningRoute(
          PlanningEntryScreen(
            relationshipId: relationshipId!,
            entryId: entryId,
          ),
        ),
      );
    },
    TogetherItem item
        when relationshipId != null &&
            item.kind == TogetherItemKind.event &&
            !item.isMaskedFor(me) =>
      () {
        final navigator = Navigator.of(context);
        final host = navigator.context;
        navigator.pop(); // close the day sheet first
        showCoupleEventSheet(host, relationshipId: relationshipId!, item: item);
      },
    ReminderModel reminder => () {
      final navigator = Navigator.of(context);
      final host = navigator.context;
      navigator.pop(); // close the day sheet first
      showReminderSheet(host, reminder: reminder);
    },
    _ => null,
  };

  /// The concrete types that reach here — a reminder, a Planning calendar
  /// entry and a Together event — all carry a real `String title`. They arrive as
  /// `Object` only because `CalendarStrip` already groups them as
  /// `List<dynamic>` upstream; matched on type rather than read
  /// through `dynamic` so a third type added later fails visibly here
  /// instead of silently rendering a generic label forever.
  String get _title => switch (entry) {
    ReminderModel(:final title) => title,
    PlanningCalendarEntry(:final title) => title,
    TogetherItem(:final title) => title,
    _ => 'Scheduled item',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same rows as above the calendar and in the Agenda: a reminder as
    // its Upcoming row (countdown included), a Together event as its row.
    switch (entry) {
      case ReminderModel reminder:
        return ReminderUpcomingRow(
          reminder: reminder,
          onTap: _onTap(context),
          last: last,
        );
      case TogetherItem item:
        return TogetherItemRow(
          item: item,
          me: me,
          partnerName:
              ref.watch(quiz_providers.partnerNameProvider).valueOrNull ??
              'Partner',
          last: last,
          onTap: _onTap(context),
        );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: _onTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              // Upcoming: the calendar's solid primary dot.
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(_title, style: textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
