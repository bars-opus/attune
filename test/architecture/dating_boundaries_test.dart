// Spec 2 W3a (§7.4, C-2, C-3, D8): Dating imports nothing from chat or
// Games; quick exit and sign-out name no Dating file; Dating's providers
// that hold data are autoDispose.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dating() => Directory('lib/features/dating')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('no chat or Games import; ChatScreen never named', () {
    for (final f in _dating()) {
      final src = f.readAsStringSync();
      expect(
        src,
        isNot(contains('package:attune/features/chat/')),
        reason: f.path,
      );
      expect(
        src,
        isNot(contains('package:attune/features/games/')),
        reason: f.path,
      );
      expect(src, isNot(contains('ChatScreen')), reason: f.path);
    }
  });

  test('quick exit and sign-out reach Dating only through the registry', () {
    for (final path in [
      'lib/features/safety/domain/services/quick_exit_service.dart',
      'lib/features/auth/providers/auth_provider.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('features/dating')), reason: path);
      // No Dating identifier (a comment may say "the Dating lock"; I-13).
      expect(src, isNot(matches(RegExp(r'\bDating[A-Z]\w*'))), reason: path);
    }
  });

  test('every Dating provider that holds data is autoDispose (D8)', () {
    final holding = RegExp(
      r'\b(FutureProvider|StreamProvider|StateProvider|StateNotifierProvider|'
      r'AsyncNotifierProvider|NotifierProvider|ChangeNotifierProvider)\b'
      r'(?!\.autoDispose)',
    );
    for (final f in _dating()) {
      for (final line in f.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        // Fix round 1 (M-1): the one exception. The Dating unlock is a
        // bool in memory, reset for each account and wiped through the
        // registry; it must outlive the screens that read it.
        if (line.contains('final datingUnlockedProvider =')) continue;
        expect(holding.hasMatch(line), isFalse, reason: '${f.path}: $line');
      }
    }
  });
}
