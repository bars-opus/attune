// Spec 1 W1c (D12): analyse-journal-entry answers {status: 'paused'} while
// journal_ai_insights is off; the model reads it and nothing reads as an
// insight.
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a paused answer parses, is paused, and is not an insight', () {
    final analysis = JournalAnalysis.fromJson(const {'status': 'paused'});
    expect(analysis.isPaused, isTrue);
    expect(analysis.isComplete, isFalse);
    expect(analysis.observation, isNull);
    expect(analysis.tone, isNull);
  });

  test('a completed answer is not paused', () {
    final analysis = JournalAnalysis.fromJson(const {
      'status': 'completed',
      'tone': 'settled',
      'observation': 'You wrote about rest.',
      'confidence': 'medium',
    });
    expect(analysis.isPaused, isFalse);
    expect(analysis.isComplete, isTrue);
  });
}
