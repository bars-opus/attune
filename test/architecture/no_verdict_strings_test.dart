// Spec 5 (R5-8, A3, review I11): the monthly summary is a "Monthly readout",
// never a "Verdict", in anything a person reads.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no "Verdict" in user-facing string literals', () {
    final hits = <String>[];
    final literal = RegExp(r"""(['"])(?:(?!\1)[^\\\n]|\\.)*\bVerdicts?\b(?:(?!\1)[^\\\n]|\\.)*\1""");
    for (final dir in ['lib/app/documentations', 'lib/features/verdict/presentation']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('import ')) continue;
          if (literal.hasMatch(line)) hits.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
