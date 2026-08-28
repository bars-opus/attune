import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitting', () {
    test('splits exactly at 60 seconds, not before', () {
      expect(
        StreakRecordingSession.shouldSplitAt(
            const Duration(seconds: 59, milliseconds: 999)),
        isFalse,
      );
      expect(
        StreakRecordingSession.shouldSplitAt(const Duration(seconds: 60)),
        isTrue,
      );
    });
  });

  group('the segment cap', () {
    test('stops once five segments are complete', () {
      expect(StreakRecordingSession.shouldStopAt(4), isFalse);
      expect(StreakRecordingSession.shouldStopAt(5), isTrue);
    });
  });

  group('previews', () {
    test('none for a single segment — a lone thumbnail is noise', () {
      expect(StreakRecordingSession.showPreviews(0), isFalse);
      expect(StreakRecordingSession.showPreviews(1), isFalse);
    });

    test('appear from the second segment', () {
      expect(StreakRecordingSession.showPreviews(2), isTrue);
    });
  });

  group('the minimum hold', () {
    test('a stray tap sends nothing', () {
      expect(
        StreakRecordingSession.shouldDiscard(
            completedSegments: 0, held: const Duration(milliseconds: 200)),
        isTrue,
      );
    });

    test('a first segment past the minimum is kept', () {
      expect(
        StreakRecordingSession.shouldDiscard(
            completedSegments: 0, held: const Duration(milliseconds: 900)),
        isFalse,
      );
    });

    test('a SHORT partial second segment is still kept', () {
      // The minimum guards a stray tap, not a deliberate release. Dropping
      // this would lose content the user watched themselves record.
      expect(
        StreakRecordingSession.shouldDiscard(
            completedSegments: 1, held: const Duration(milliseconds: 200)),
        isFalse,
      );
    });
  });
}
