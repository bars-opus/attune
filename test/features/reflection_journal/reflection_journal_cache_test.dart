import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/reflection_journal/data/cache/reflection_journal_cache.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userA = 'user-aaa';
const _userB = 'user-bbb';

JournalEntry _entry(String id, {String content = 'entry content'}) {
  return JournalEntry(
    id: id,
    userId: _userA,
    content: content,
    promptUsed: 'What made today good?',
    tone: 'reflective',
    createdAt: DateTime.utc(2026, 8, 1, 9),
    updatedAt: DateTime.utc(2026, 8, 1, 9),
  );
}

Future<ReflectionJournalCache> _makeCache() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container.read(reflectionJournalCacheProvider);
}

void main() {
  group('ReflectionJournalCache', () {
    test('round-trips every field an entry carries', () async {
      final cache = await _makeCache();
      final original = _entry('e1', content: 'Today I felt calmer.');

      await cache.writeEntries(_userA, [original]);
      final restored = cache.readEntries(_userA).single;

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.content, original.content);
      expect(restored.promptUsed, original.promptUsed);
      expect(restored.tone, original.tone);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('handles null promptUsed/tone', () async {
      final cache = await _makeCache();
      final noPrompt = JournalEntry(
        id: 'e2',
        userId: _userA,
        content: 'no prompt used',
        promptUsed: null,
        tone: null,
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
      );

      await cache.writeEntries(_userA, [noPrompt]);
      final restored = cache.readEntries(_userA).single;

      expect(restored.promptUsed, isNull);
      expect(restored.tone, isNull);
    });

    test('returns empty on a cold miss', () async {
      final cache = await _makeCache();
      expect(cache.readEntries(_userA), isEmpty);
    });

    test('isolates users', () async {
      final cache = await _makeCache();
      await cache.writeEntries(_userA, [_entry('a')]);

      expect(cache.readEntries(_userB), isEmpty);
      expect(cache.readEntries(_userA), isNotEmpty);
    });

    test('treats a corrupt payload as a miss', () async {
      SharedPreferences.setMockInitialValues({
        'reflection_journal_cache_${_userA}_entries': 'not valid json{{',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final cache = container.read(reflectionJournalCacheProvider);

      expect(cache.readEntries(_userA), isEmpty);
    });

    test('overwrites rather than appending on repeat writes', () async {
      final cache = await _makeCache();

      await cache.writeEntries(_userA, [_entry('first')]);
      await cache.writeEntries(_userA, [_entry('second')]);

      final restored = cache.readEntries(_userA);
      expect(restored, hasLength(1));
      expect(restored.single.id, 'second');
    });
  });
}
