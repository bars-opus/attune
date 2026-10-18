// test/features/chat/no_streak_counter_gate_test.dart
// Spec 1b (research 06 §3 F6 (2); SOUL §5 P1, no streaks): the chat streak
// counter is gone and must not come back. Chat providers never mention a
// streak, and nothing in lib/ calls the counter or reads its flag. The
// streak CAMERA lives in presentation/state, data/streak_repository.dart and
// the settings feature -- outside this gate on purpose.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dart(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('chat providers never mention a streak', () {
    final hits = <String>[];
    for (final f in _dart('lib/features/chat/presentation/providers')) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp('streak', caseSensitive: false).hasMatch(lines[i])) {
          hits.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty);
  });

  test('nothing in lib/ calls the counter or reads its flag', () {
    final hits = [
      for (final f in _dart('lib'))
        if (RegExp(
          r'chat_conversation_streak|chat_streaks|fetchStreak',
        ).hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(hits, isEmpty);
  });
}
