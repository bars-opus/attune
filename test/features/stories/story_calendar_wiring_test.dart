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
void main() {
  final timelineScreen = File(
    'lib/features/timeline/presentation/screens/timeline_screen.dart',
  ).readAsStringSync();

  test('the timeline screen renders the story day row', () {
    expect(
      timelineScreen.contains('StoryDayCountRow('),
      isTrue,
      reason:
          'stories leave the reel after 24h but stay in the calendar '
          'forever (spec §1/§3.1) — without this the permanence half of '
          'the feature is invisible in the app',
    );
  });

  test('it passes the selected day, so the row is day-scoped', () {
    expect(
      timelineScreen.contains('occurredOn: _selectedDate!'),
      isTrue,
      reason:
          'the row is composed at read time for the SELECTED day; a '
          'hardcoded or missing date would show the wrong day\'s stories',
    );
  });

  test('it passes the relationship, so it cannot read another couple', () {
    expect(
      RegExp(
        r'StoryDayCountRow\(\s*relationshipId: relationshipId,',
      ).hasMatch(timelineScreen),
      isTrue,
      reason:
          'the row must be scoped to this couple; the RPC and RLS are the '
          'real authority, but passing the wrong id here would read as an '
          'empty calendar rather than an error',
    );
  });
}
