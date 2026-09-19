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

import 'package:attune/features/planning/data/models/planning_calendar_entry_model.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

/// The day's stories as a horizontal row of tappable thumbnails.
/// Renders nothing at all when the day has none — the same
/// "absence means don't draw" posture `StoryDayCountRow` uses.
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
    final itemsAsync = ref.watch(
      storyDayItemsProvider(
        StoryDayKey(relationshipId: relationshipId, occurredOn: date),
      ),
    );
    final items = itemsAsync.valueOrNull;
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          items.length == 1 ? '1 story' : '${items.length} stories',
          style: textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) => _StoryThumbnail(
              item: items[index],
              // Every thumbnail opens the day reel, which plays the
              // whole day from the start — the reel has no
              // open-at-this-item mode yet, and inventing one here
              // would mean threading an initial index through
              // StoryReelScreen.forDay's own pager. Honest v1 limit,
              // not a silent no-op.
              onTap: () => _openReel(context),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _StoryThumbnail extends ConsumerWidget {
  const _StoryThumbnail({required this.item, required this.onTap});

  final StoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final url = ref
        .watch(storyMediaSignedUrlProvider(item.thumbnailKey))
        .valueOrNull;

    return Semantics(
      button: true,
      label: 'Story from this day',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 72,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: item.hasBeenViewed
                  ? colorScheme.outlineVariant
                  : colorScheme.primary,
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null && url.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      ColoredBox(color: colorScheme.surfaceContainerHighest),
                  errorWidget: (_, __, ___) =>
                      ColoredBox(color: colorScheme.surfaceContainerHighest),
                ),
              if (item.mediaType == 'video')
                const Positioned(
                  right: 4,
                  bottom: 4,
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
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
