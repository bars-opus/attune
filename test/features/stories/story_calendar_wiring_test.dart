import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The calendar's story row reaches the actual timeline screen.
///
/// `story_calendar_test.dart` mounts `StoryDayRow`/`StoryDayCountRow`
/// directly in a bare Scaffold, so it proves they BEHAVE correctly and
/// says nothing about whether `TimelineScreen` ever renders one. Deleting
/// the wiring from `timeline_screen.dart` outright — removing the whole
/// memory-lane integration, the thing the feature exists for — left all
/// 151 story and timeline tests passing.
///
/// The unused-import lint would not have caught it either: analysing
/// `timeline_screen.dart` with the import orphaned reports "No issues
/// found", because that lint is not enabled in this project.
///
/// A source check rather than a screen test, following
/// `test/features/chat/game_staged_wiring_test.dart`'s precedent for the
/// same shape of gap: TimelineScreen needs Supabase, a relationship and
/// several live providers to build, which is why nothing in `test/`
/// mounts it to hang this on.
/// **Reachability moved, not removed.** The story day row used to sit
/// inline under the calendar (`StoryDayCountRow`). Tapping a date now
/// opens `CalendarDaySheet` instead, which renders that day's stories as
/// a tappable thumbnail row, and the calendar's own date cells draw a
/// story avatar per author via `CalendarDayIndicators`. The property
/// these tests guard is unchanged — a past day's stories must still be
/// reachable from the calendar — so they assert on the new wiring rather
/// than the retired widget name.
void main() {
  final timelineScreen = File(
    'lib/features/timeline/presentation/screens/timeline_screen.dart',
  ).readAsStringSync();
  final calendarStrip = File(
    'lib/features/timeline/presentation/widgets/calendar_strip.dart',
  ).readAsStringSync();
  final daySheet = File(
    'lib/features/timeline/presentation/widgets/calendar_day_sheet.dart',
  ).readAsStringSync();

  test('tapping a calendar date opens the day sheet', () {
    expect(
      timelineScreen.contains('_openDaySheet(') &&
          timelineScreen.contains('showCalendarDaySheet('),
      isTrue,
      reason:
          'stories leave the reel after 24h but stay in the calendar '
          'forever (spec §1/§3.1) — the day sheet is now the way into a '
          'past day, so without this the permanence half of the feature '
          'is unreachable in the app',
    );
  });

  test('the day sheet renders that day\'s stories', () {
    expect(
      daySheet.contains('storyDayItemsProvider('),
      isTrue,
      reason:
          "the sheet must compose the day's stories at read time; without "
          'this it would show only events and the stories would be '
          'invisible again',
    );
  });

  test('the sheet is opened for the tapped day, so it is day-scoped', () {
    expect(
      RegExp(
        r'showCalendarDaySheet\([\s\S]{0,300}?date: date,',
      ).hasMatch(timelineScreen),
      isTrue,
      reason:
          'the sheet is composed for the TAPPED day; a hardcoded or '
          "missing date would show the wrong day's stories",
    );
  });

  test('it passes the relationship, so it cannot read another couple', () {
    expect(
      RegExp(
        r'showCalendarDaySheet\([\s\S]{0,300}?relationshipId: relationshipId,',
      ).hasMatch(timelineScreen),
      isTrue,
      reason:
          'the sheet must be scoped to this couple; the RPC and RLS are '
          'the real authority, but passing the wrong id here would read '
          'as an empty calendar rather than an error',
    );
  });

  test('calendar date cells draw per-author story avatars', () {
    expect(
      calendarStrip.contains('CalendarDayIndicators(') &&
          calendarStrip.contains('relationshipId: relationshipId'),
      isTrue,
      reason:
          'a date with stories must be visibly distinguishable in the '
          'grid itself, not only after tapping it',
    );
  });
}
