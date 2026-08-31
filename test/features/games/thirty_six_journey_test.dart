import 'package:attune/features/games/thirty_six_questions/data/models/thirty_six_question_chapter.dart';
import 'package:attune/features/games/thirty_six_questions/data/models/thirty_six_question_journey.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 12);

ThirtySixQuestionJourney _journey({
  String status = 'in_progress',
  bool ch1 = false,
  bool ch2 = false,
  bool ch3 = false,
  String? finalObservation,
}) => ThirtySixQuestionJourney(
  id: 'j1',
  relationshipId: 'r1',
  status: status,
  chapter1CompletedAt: ch1 ? _now : null,
  chapter2CompletedAt: ch2 ? _now : null,
  chapter3CompletedAt: ch3 ? _now : null,
  finalObservation: finalObservation,
  createdAt: _now,
  updatedAt: _now,
);

ThirtySixQuestionChapter _chapter({
  required String status,
  int skipsUsed = 0,
}) => ThirtySixQuestionChapter(
  sessionId: 's1',
  journeyId: 'j1',
  chapterNumber: 1,
  status: status,
  skipsUsed: skipsUsed,
  createdAt: _now,
);

void main() {
  group('the journey (36_QUESTIONS.md §1: 3 chapters of 12)', () {
    test('a fresh journey starts at chapter 1', () {
      expect(_journey().completedChapters, 0);
      expect(_journey().nextChapter, 1);
      expect(_journey().isFullyCompleted, isFalse);
    });

    test('each completed chapter advances the next one', () {
      expect(_journey(ch1: true).nextChapter, 2);
      expect(_journey(ch1: true, ch2: true).nextChapter, 3);
    });

    test('all three chapters completes the journey', () {
      final done = _journey(ch1: true, ch2: true, ch3: true);
      expect(done.completedChapters, 3);
      expect(done.isFullyCompleted, isTrue);
      // 4 is out of range; the overview screen gates on nextChapter <= 3.
      expect(done.nextChapter, 4);
    });

    test('a final observation must be non-empty to count as present', () {
      // An empty string would otherwise render a blank observation card at
      // the end of the whole journey.
      expect(_journey().hasFinalObservation, isFalse);
      expect(_journey(finalObservation: '').hasFinalObservation, isFalse);
      expect(_journey(finalObservation: 'a note').hasFinalObservation, isTrue);
    });
  });

  group('a chapter', () {
    test('reports its status exclusively', () {
      final active = _chapter(status: 'active');
      expect(active.isActive, isTrue);
      expect(active.isInvited, isFalse);
      expect(active.isCompleted, isFalse);
      expect(active.isAbandoned, isFalse);
    });

    test('allows two skips, then no more', () {
      // §"skips": two per chapter. The boundary is what matters — an
      // off-by-one here either steals a skip or grants a third.
      expect(_chapter(status: 'active', skipsUsed: 0).hasSkipsRemaining, isTrue);
      expect(_chapter(status: 'active', skipsUsed: 1).hasSkipsRemaining, isTrue);
      expect(
        _chapter(status: 'active', skipsUsed: 2).hasSkipsRemaining,
        isFalse,
      );
    });
  });
}
