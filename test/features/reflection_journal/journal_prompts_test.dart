import 'package:attune/features/reflection_journal/data/journal_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journalPrompts has at least 30 entries, all non-empty and unique', () {
    expect(journalPrompts.length, greaterThanOrEqualTo(30));
    expect(journalPrompts.toSet().length, journalPrompts.length);
    for (final prompt in journalPrompts) {
      expect(prompt.trim(), isNotEmpty);
    }
  });

  test('no prompt is a yes/no question', () {
    for (final prompt in journalPrompts) {
      final lower = prompt.toLowerCase();
      final startsYesNo = lower.startsWith('did ') ||
          lower.startsWith('do you ') ||
          lower.startsWith('are you ') ||
          lower.startsWith('is ') ||
          lower.startsWith('was ');
      expect(startsYesNo, isFalse, reason: 'yes/no-shaped: $prompt');
    }
  });

  test('randomJournalPrompt with a fixed seed is deterministic', () {
    final a = randomJournalPrompt(seed: 42);
    final b = randomJournalPrompt(seed: 42);
    expect(a, b);
    expect(journalPrompts, contains(a));
  });
}
