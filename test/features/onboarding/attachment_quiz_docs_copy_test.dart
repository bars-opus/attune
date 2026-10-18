// Spec 5 (research 06 §3 F9 (3)): the attachment result is about you. The
// quiz's own docs never promise compatibility or a partner-facing reading.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attachment quiz docs promise no compatibility and no partner view', () {
    final src = File(
      'lib/features/onboarding/presentation/data/attachment_quiz_docs.dart',
    ).readAsStringSync();
    expect(src.toLowerCase(), isNot(contains('compatibility')));
    expect(src, isNot(contains('derived from both of your answers')));
    expect(src, contains('Your partner never sees your attachment result'));
  });
}
