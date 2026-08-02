import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JournalEntry.fromJson parses all fields', () {
    final entry = JournalEntry.fromJson({
      'id': 'entry-1',
      'user_id': 'user-1',
      'content': 'Today was hard.',
      'prompt_used': "What's one thing that surprised you today?",
      'tone': 'heavy',
      'created_at': '2026-08-01T10:00:00Z',
      'updated_at': '2026-08-01T10:00:00Z',
    });

    expect(entry.id, 'entry-1');
    expect(entry.userId, 'user-1');
    expect(entry.content, 'Today was hard.');
    expect(entry.promptUsed, "What's one thing that surprised you today?");
    expect(entry.tone, 'heavy');
    expect(entry.createdAt, DateTime.parse('2026-08-01T10:00:00Z'));
  });

  test('JournalEntry.fromJson handles null prompt_used and tone', () {
    final entry = JournalEntry.fromJson({
      'id': 'entry-2',
      'user_id': 'user-1',
      'content': 'Quick note.',
      'prompt_used': null,
      'tone': null,
      'created_at': '2026-08-01T10:00:00Z',
      'updated_at': '2026-08-01T10:00:00Z',
    });

    expect(entry.promptUsed, isNull);
    expect(entry.tone, isNull);
  });

  test('JournalAnalysis.fromJson parses a completed analysis', () {
    final analysis = JournalAnalysis.fromJson({
      'status': 'completed',
      'tone': 'reflective',
      'observation': 'You described feeling unheard in this entry.',
      'confidence': 'medium',
    });

    expect(analysis.status, 'completed');
    expect(analysis.tone, 'reflective');
    expect(analysis.observation, 'You described feeling unheard in this entry.');
    expect(analysis.confidence, 'medium');
    expect(analysis.isComplete, isTrue);
  });

  test('JournalAnalysis.fromJson handles insufficient_evidence with nulls', () {
    final analysis = JournalAnalysis.fromJson({
      'status': 'insufficient_evidence',
      'tone': null,
      'observation': null,
      'confidence': 'none',
    });

    expect(analysis.isComplete, isFalse);
    expect(analysis.observation, isNull);
  });
}
