// Batch-1 review #3: core prefs (imported by sign-out and most tests) stays
// light: it may read a feature's data constants, never a presentation file,
// which would pull in the router and screen graph.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared_preferences_service.dart imports no presentation file', () {
    final source =
        File(
          'lib/core/services/shared_preferences_service.dart',
        ).readAsStringSync();
    final imports =
        RegExp(
          r"^import '([^']+)';",
          multiLine: true,
        ).allMatches(source).map((m) => m.group(1)!).toList();
    expect(imports, isNotEmpty);
    for (final uri in imports) {
      expect(uri, isNot(contains('/presentation/')), reason: uri);
      expect(uri, isNot(contains('/routing/')), reason: uri);
    }
  });
}
