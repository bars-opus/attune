// Spec 2 W3a (R11, R21, I-4; W1 B10 M-9): the app reads Dating only through
// RPCs, never calls the dropped shim, and keeps no v1 writer or purpose.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _libDart() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (f) => f.path.endsWith('.dart') && !f.path.contains('/i10n/generated/'),
    );

void _noneMatch(RegExp pattern) {
  final hits = [
    for (final f in _libDart())
      if (pattern.hasMatch(f.readAsStringSync())) f.path,
  ];
  expect(hits, isEmpty, reason: pattern.pattern);
}

void main() {
  test("no direct read of a Dating table (.from('dating_…'))", () {
    _noneMatch(RegExp(r'''\.from\(\s*['"]dating_'''));
  });
  test('no caller of get_dating_eligibility', () {
    _noneMatch(RegExp('get_dating_eligibility'));
  });
  test('no v1 writer: delete_dating_profile, save_dating_profile_draft', () {
    _noneMatch(RegExp(r'delete_dating_profile(?!_photo)'));
    _noneMatch(RegExp('save_dating_profile_draft'));
  });
  test("no v1 consent purpose: 'historical_data', 'age_gate'", () {
    _noneMatch(RegExp(r'''['"](historical_data|age_gate)['"]'''));
  });
}
