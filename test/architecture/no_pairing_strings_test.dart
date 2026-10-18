// Spec 5 (research 06 §3 F9 (2), (4)): no screen, push, card or export ever
// contains a pairing or type statement about the couple. The app's Dart
// source carries none of the pairing machinery's words.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no pairing words in lib/**/*.dart', () {
    final patterns = <RegExp>[
      RegExp(r'\bpairingName\b'),
      RegExp(r'\bpairingDescription\b'),
      RegExp(r'\bnatural_strength\b'),
      RegExp(r'\bnaturalStrength\b'),
      RegExp(r'\bwatchArea\b'),
      RegExp(r'attachment pairing', caseSensitive: false),
      RegExp(r'how your styles fit together', caseSensitive: false),
      RegExp(r'how your styles compare', caseSensitive: false),
      RegExp(r'compatibility preview', caseSensitive: false),
    ];
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final p in patterns) {
          if (p.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}: ${p.pattern}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
