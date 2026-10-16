import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the September location spec says its §2 was replaced', () {
    final s = File('docs/superpowers/specs/2026-09-02-location-presence-design.md').readAsStringSync();
    expect(s.contains('Replaced (2026-10-16)'), isTrue);
  });

  test('the couple map spec records each phase status', () {
    final s = File('docs/superpowers/specs/2026-10-16-couple-map-design.md').readAsStringSync();
    expect(s.contains('| # | What ships | Risk | Status |'), isTrue);
  });
}
