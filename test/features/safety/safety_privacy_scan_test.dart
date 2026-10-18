// Spec 2 (research 06 §3 F3 (4)): nothing in the safety or account features
// writes to the device log; a log can hold a PIN, a session or a push id.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no logging in lib/features/safety or lib/features/account', () {
    final logging = RegExp(r'debugPrint|\bprint\(|\blog\(|developer\.log');
    final hits = <String>[];
    for (final dir in ['lib/features/safety', 'lib/features/account']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (logging.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty);
  });
}
