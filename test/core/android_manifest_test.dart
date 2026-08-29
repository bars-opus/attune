import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every permission the app relies on is declared', () {
    // Android SILENTLY ignores an undeclared permission — no error, no
    // log. HapticFeedback calls simply never landed, which presented as
    // "haptics work sometimes" and cost several rounds of chasing Dart
    // state that was never the problem.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    const required = {
      'VIBRATE': 'HapticFeedback throughout the app',
      'RECORD_AUDIO': 'voice messages and streak audio',
      'CAMERA': 'streak and ephemeral capture',
      'INTERNET': 'everything',
    };

    for (final entry in required.entries) {
      expect(
        manifest,
        contains('android.permission.${entry.key}'),
        reason: '${entry.key} is needed for ${entry.value}',
      );
    }
  });
}
