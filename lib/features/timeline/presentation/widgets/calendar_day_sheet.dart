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

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/planning/data/models/planning_calendar_entry_model.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
    builder: (_) => CalendarDaySheet(
      relationshipId: relationshipId,
      date: date,
      events: events,
      reminders: reminders,
      planningEntries: planningEntries,
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
  });

  final String? relationshipId;
  final DateTime date;
  final List<TimelineEventModel> events;
  final List<dynamic> reminders;
  final List<dynamic> planningEntries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('EEEE, MMMM d, yyyy').format(date),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
                for (final entry in [...reminders, ...planningEntries])
                  _ScheduledTile(entry: entry),
              ],
              if (events.isEmpty &&
                  reminders.isEmpty &&
                  planningEntries.isEmpty &&
                  relationshipId == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nothing on this day yet.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The day's stories as ONE RING PER AUTHOR, matching how stories are
/// presented on the conversations screen (`StoryRingsRow`) — a day both
/// partners posted on shows two rings side by side, each segmented by
/// that author's own item count for the day.
///
/// Deliberately NOT built on `storyRingSummaryProvider`, which
/// `StoryRingsRow` uses: that provider is relationship-wide and
/// ACTIVE-only, whereas this sheet is scoped to one date and must
/// include expired items (stories spec §1/§3.2 — expiry removes a story
/// from the reel, never from the calendar). The rings here are composed
/// from `storyDayItemsProvider`, grouped by author, so an expired story
/// still fills its author's ring years later.
///
/// Renders nothing at all when the day has none — the same "absence
/// means don't draw" posture `StoryDayCountRow` uses.
class _StoriesSection extends ConsumerWidget {
  const _StoriesSection({required this.relationshipId, required this.date});

  final String relationshipId;
  final DateTime date;

  void _openReel(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StoryReelScreen.forDay(
          relationshipId: relationshipId,
          occurredOn: date,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final itemsAsync = ref.watch(
      storyDayItemsProvider(
        StoryDayKey(relationshipId: relationshipId, occurredOn: date),
      ),
    );
    final items = itemsAsync.valueOrNull;
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    // Group by author, preserving the provider's oldest-first order so
    // "newest" below is genuinely the last item, not an arbitrary one.
    final byAuthor = <String, List<StoryItem>>{};
    for (final item in items) {
      byAuthor.putIfAbsent(item.authorId, () => []).add(item);
    }

    // My own ring first when I posted that day, mirroring
    // StoryRingsRow's mine-then-partner order.
    final authorIds = byAuthor.keys.toList()
      ..sort((x, y) {
        if (x == myId) return -1;
        if (y == myId) return 1;
        return x.compareTo(y);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          items.length == 1 ? '1 story' : '${items.length} stories',
          style: textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height:
              kStoryRingThumbnailDiameter +
              2 * (kStoryRingGap + kStoryRingStrokeWidth) +
              4,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: authorIds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, index) {
              final authorId = authorIds[index];
              return _AuthorDayRing(
                key: ValueKey('day-story-ring-$authorId'),
                items: byAuthor[authorId]!,
                isMine: authorId == myId,
                // Both rings open the same day reel:
                // StoryReelScreen.forDay plays the whole day and has no
                // per-author mode (its own `authorId` field is unused in
                // day mode). Filtering to one author would mean a new
                // constructor and pager, so this stays honest rather
                // than pretending the rings route differently.
                onTap: () => _openReel(context),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// One author's ring for one calendar day, drawn with the same
/// [StoryRing] the conversations screen uses.
class _AuthorDayRing extends ConsumerWidget {
  const _AuthorDayRing({
    super.key,
    required this.items,
    required this.isMine,
    required this.onTap,
  });

  /// This author's items for the day, oldest first.
  final List<StoryItem> items;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newest = items.last;
    final thumbnailUrl = ref
        .watch(storyMediaSignedUrlProvider(newest.thumbnailKey))
        .valueOrNull;

    // `hasBeenViewed` on MY OWN story means "my partner saw it", not
    // "I saw it" (StoryItem's own doc comment), so it says nothing
    // about whether I have seen mine — every segment of my own ring
    // renders bright, exactly as StoryRingsRow does for the same
    // reason. For the partner's ring it means what it says.
    final unviewedCount = isMine
        ? items.length
        : items.where((i) => !i.hasBeenViewed).length;

    return StoryRing(
      isMine: isMine,
      hasStories: true,
      segmentCount: items.length,
      unviewedCount: unviewedCount,
      thumbnailUrl: thumbnailUrl,
      onTap: onTap,
      // No `+` affordance in the calendar: this sheet looks at a past
      // day, and a capture would post to TODAY, not to the day being
      // viewed. StoryRing only draws the badge when isMine, and
      // leaving onTapPlus null makes it inert rather than silently
      // posting to the wrong date.
      semanticLabel: isMine
          ? 'Your stories from this day, ${items.length} '
                '${items.length == 1 ? 'item' : 'items'}'
          : 'Your partner\'s stories from this day, ${items.length} '
                '${items.length == 1 ? 'item' : 'items'}',
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

class _ScheduledTile extends StatelessWidget {
  const _ScheduledTile({required this.entry});

  final Object entry;

  /// The two concrete types that reach here — a reminder and a Planning
  /// calendar entry — both carry a real `String title`. They arrive as
  /// `Object` only because `CalendarStrip` already groups them as
  /// `List<dynamic>` upstream; matched on type rather than read
  /// through `dynamic` so a third type added later fails visibly here
  /// instead of silently rendering a generic label forever.
  String get _title => switch (entry) {
    ReminderModel(:final title) => title,
    PlanningCalendarEntryModel(:final title) => title,
    _ => 'Scheduled item',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.secondary, width: 1.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(_title, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
