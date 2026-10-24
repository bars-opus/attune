/// What a calendar date cell draws underneath its day number: a small
/// story thumbnail avatar per author who posted that day (one per
/// partner, so a day both posted on shows two), and circular color-keyed
/// avatars for the day's events/reminders/planning entries.
///
/// Stories are composed at read time from `storyDayCountsProvider` —
/// never copied into `timeline_events` — the same posture
/// `StoryDayCountRow` documents. Since migration 20260951010000 that
/// provider returns one row PER AUTHOR per day, which is what makes the
/// per-partner avatars here possible at all; before it, a date could only
/// say "N stories", with no author or thumbnail breakdown.
///
/// Expiry is deliberately NOT filtered here: an expired story leaves the
/// reel but stays in the couple's calendar forever (stories spec §1,
/// §3.2). This widget does no date arithmetic of its own.
library;

import 'package:attune/features/reminders/presentation/reminder_icons.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Diameter of one story thumbnail avatar in a date cell. Small enough
/// that two sit side by side inside a ~40dp grid cell under the day
/// number without overflowing.
const double kCalendarStoryAvatarDiameter = 14;

/// Diameter of one event avatar. Matches the story avatar so a date with
/// both reads as one consistent row of circles rather than two scales.
const double kCalendarEventAvatarDiameter = 14;

/// At most this many indicator circles per cell before the rest collapse
/// into a "+N" tile — two partners' stories plus a couple of events is
/// already the practical ceiling for a cell this size.
const int kCalendarMaxIndicators = 3;

/// The canonical event-type -> color mapping, shared by the date cells
/// and the legend below the calendar so the two can never drift.
Color calendarEventTypeColor(String eventType, ColorScheme colorScheme) {
  switch (eventType) {
    case 'milestone':
      return colorScheme.primary;
    case 'conflict':
      return const Color(0xFFD32F2F);
    case 'highlight':
      return const Color(0xFFFFA000);
    case 'first':
      return const Color(0xFF7B1FA2);
    case 'anniversary':
      return const Color(0xFFC2185B);
    default:
      return colorScheme.primary;
  }
}

/// The icon drawn inside an event avatar. Color alone does not satisfy
/// WCAG 1.4.1 — every event type is distinguishable by glyph too, the
/// same reasoning `_SegmentedRingPainter` applies to viewed/unviewed
/// story arcs.
IconData calendarEventTypeIcon(String eventType) {
  switch (eventType) {
    case 'milestone':
      return Icons.flag;
    case 'conflict':
      return Icons.bolt;
    case 'highlight':
      return Icons.star;
    case 'first':
      return Icons.auto_awesome;
    case 'anniversary':
      return Icons.favorite;
    default:
      return Icons.circle;
  }
}

/// Human-readable label per event type, for the legend and for
/// screen readers.
String calendarEventTypeLabel(String eventType) {
  switch (eventType) {
    case 'milestone':
      return 'Milestone';
    case 'conflict':
      return 'Conflict';
    case 'highlight':
      return 'Highlight';
    case 'first':
      return 'First';
    case 'anniversary':
      return 'Anniversary';
    default:
      return eventType;
  }
}

/// The indicator row for one date cell.
class CalendarDayIndicators extends ConsumerWidget {
  const CalendarDayIndicators({
    super.key,
    required this.relationshipId,
    required this.date,
    required this.eventTypes,
    this.reminderTypes = const [],
    required this.hasUpcoming,
  });

  final String? relationshipId;
  final DateTime date;

  /// Distinct event types logged on this date, in display order.
  final List<String> eventTypes;

  /// The occasions of this date's reminders (birthday, anniversary…). The
  /// first is drawn as its occasion icon in its own colour, the same mark
  /// that ends its row in the Upcoming list; the day sheet lists the rest.
  final List<String?> reminderTypes;

  /// Whether this date carries a Planning task/event or Together plan — the
  /// "not yet happened" signal with no occasion, drawn as a small solid
  /// primary dot (no glyph, smaller than a moment's avatar).
  final bool hasUpcoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storyAuthors = _storyAuthorsFor(ref);

    final indicators = <Widget>[
      for (final author in storyAuthors.take(kCalendarMaxIndicators))
        _StoryAvatar(
          key: ValueKey('cal-story-${author.authorId ?? 'unknown'}'),
          thumbnailKey: author.newestThumbnailKey,
        ),
    ];

    final remaining = kCalendarMaxIndicators - indicators.length;
    if (remaining > 0) {
      for (final type in eventTypes.take(remaining)) {
        indicators.add(_EventAvatar(eventType: type));
      }
    }

    final hiddenCount =
        (storyAuthors.length + eventTypes.length) - indicators.length;

    if (indicators.isEmpty && reminderTypes.isEmpty && !hasUpcoming) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final indicator in indicators)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: indicator,
            ),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _OverflowTile(count: hiddenCount),
            ),
          if (reminderTypes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _OccasionMark(type: reminderTypes.first),
            ),
          if (hasUpcoming)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 0.5),
              child: _UpcomingRing(),
            ),
        ],
      ),
    );
  }

  /// Every author with at least one story on [date], newest-posting
  /// author first (the RPC's own ORDER BY).
  List<StoryDayCount> _storyAuthorsFor(WidgetRef ref) {
    final id = relationshipId;
    if (id == null) return const [];

    final monthStart = DateTime(date.year, date.month, 1);
    final monthEnd = DateTime(date.year, date.month + 1, 0);
    final counts =
        ref
            .watch(
              storyDayCountsProvider(
                StoryDayRangeKey(
                  relationshipId: id,
                  startOn: monthStart,
                  endOn: monthEnd,
                ),
              ),
            )
            .valueOrNull;
    if (counts == null) return const [];

    return counts
        .where(
          (c) =>
              c.occurredOn.year == date.year &&
              c.occurredOn.month == date.month &&
              c.occurredOn.day == date.day &&
              c.itemCount > 0,
        )
        .toList(growable: false);
  }
}

/// One author's newest story thumbnail for the day, clipped to a circle
/// with a thin ring so it reads as story media rather than a plain dot.
class _StoryAvatar extends ConsumerWidget {
  const _StoryAvatar({super.key, required this.thumbnailKey});

  final String? thumbnailKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final key = thumbnailKey;
    // Only mint a signed URL when there is actually a key to sign —
    // mirrors _PartnerRing's own scoping in story_rings_row.dart.
    final url =
        (key == null || key.isEmpty)
            ? null
            : ref.watch(storyMediaSignedUrlProvider(key)).valueOrNull;
    final decodeWidth = storyThumbnailDecodeWidth(
      kCalendarStoryAvatarDiameter,
      MediaQuery.maybeDevicePixelRatioOf(context) ?? 3,
    );

    return Container(
      width: kCalendarStoryAvatarDiameter,
      height: kCalendarStoryAvatarDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.primary, width: 1.2),
      ),
      child: ClipOval(
        child:
            (key != null && key.isNotEmpty)
                // One widget before and after the URL lands: the disk copy
                // stays up until the network image is ready.
                ? StoryKeyCachedImage(
                  storageKey: key,
                  imageUrl: url,
                  decodeWidth: decodeWidth,
                  fadeInDuration: const Duration(milliseconds: 500),
                  fallback: ColoredBox(
                    color: colorScheme.surfaceContainerHighest,
                  ),
                )
                : ColoredBox(color: colorScheme.surfaceContainerHighest),
      ),
    );
  }
}

/// A logged moment: a filled, color-keyed circle carrying the type's own
/// glyph so the type survives a colorblind reading.
class _EventAvatar extends StatelessWidget {
  const _EventAvatar({required this.eventType});

  final String eventType;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = calendarEventTypeColor(eventType, colorScheme);

    return Semantics(
      label: calendarEventTypeLabel(eventType),
      child: Container(
        width: kCalendarEventAvatarDiameter,
        height: kCalendarEventAvatarDiameter,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        alignment: Alignment.center,
        child: Icon(
          calendarEventTypeIcon(eventType),
          size: kCalendarEventAvatarDiameter * 0.6,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Size of a reminder's occasion icon in a date cell: legible, and no
/// taller than a moment's avatar.
const double kCalendarOccasionIconSize = 12;

/// A reminder's occasion — the cake, the champagne glasses… — bare, in its
/// occasion colour, so it matches its row above the calendar and reads
/// apart from a moment's filled circle.
class _OccasionMark extends StatelessWidget {
  const _OccasionMark({required this.type});

  final String? type;

  @override
  Widget build(BuildContext context) => Semantics(
    label: reminderOccasionLabel(type),
    child: Icon(
      reminderOccasionIcon(type),
      size: kCalendarOccasionIconSize,
      color: reminderOccasionColor(type, context),
    ),
  );
}

/// "A plan ahead here" — a solid dot in the primary colour, for what has
/// no occasion of its own (stories keep their outline).
class _UpcomingRing extends StatelessWidget {
  const _UpcomingRing();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Upcoming',
      child: Container(
        width: kCalendarEventAvatarDiameter * 0.55,
        height: kCalendarEventAvatarDiameter * 0.55,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

class _OverflowTile extends StatelessWidget {
  const _OverflowTile({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: kCalendarEventAvatarDiameter,
      height: kCalendarEventAvatarDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surfaceContainerHighest,
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: TextStyle(
          fontSize: kCalendarEventAvatarDiameter * 0.45,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// The color-key legend under the calendar. Renders only the types the
/// visible month actually contains, so it stays a key to what is on
/// screen rather than a static list of every type the app supports.
class CalendarLegend extends StatelessWidget {
  const CalendarLegend({
    super.key,
    required this.eventTypes,
    this.reminderTypes = const [],
    required this.hasStories,
    required this.hasUpcoming,
  });

  final List<String> eventTypes;

  /// The reminder occasions shown this month, each keyed with its icon.
  final List<String?> reminderTypes;
  final bool hasStories;
  final bool hasUpcoming;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final entries = <Widget>[
      if (hasStories)
        _LegendEntry(
          label: 'Story',
          swatch: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainerHighest,
              border: Border.all(color: colorScheme.primary, width: 1.2),
            ),
          ),
        ),
      for (final type in eventTypes)
        _LegendEntry(
          label: calendarEventTypeLabel(type),
          swatch: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: calendarEventTypeColor(type, colorScheme),
            ),
            alignment: Alignment.center,
            child: Icon(
              calendarEventTypeIcon(type),
              size: 6,
              color: Colors.white,
            ),
          ),
        ),
      for (final type in reminderTypes)
        _LegendEntry(
          label: reminderOccasionLabel(type),
          swatch: Icon(
            reminderOccasionIcon(type),
            size: 10,
            color: reminderOccasionColor(type, context),
          ),
        ),
      if (hasUpcoming)
        _LegendEntry(
          label: 'Upcoming',
          swatch: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary,
            ),
          ),
        ),
    ];

    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final entry in entries)
            DefaultTextStyle(
              style:
                  textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ) ??
                  const TextStyle(fontSize: 11),
              child: entry,
            ),
        ],
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.label, required this.swatch});

  final String label;
  final Widget swatch;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [swatch, const SizedBox(width: 4), Text(label)],
    );
  }
}
