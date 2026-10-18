// Spec 2 (review I9): the manual describes the PIN and quick exit as built.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src =
      File(
        'lib/app/documentations/user_manual/data/safety_docs.dart',
      ).readAsStringSync();

  test('no promise the PIN cannot honestly keep', () {
    expect(src, isNot(contains('cannot be bypassed')));
    expect(src, isNot(contains('Setting up Quick Exit requires')));
    expect(src, isNot(contains('Attune logo')));
    // iOS cannot close an app (review M-4).
    expect(src, isNot(contains('unbranded screen and closes')));
    expect(src, contains('on Android it also closes'));
  });

  test('says where to set the PIN, when it is asked and how to recover', () {
    expect(src, contains('Settings → Safety PIN'));
    expect(src, contains('every time Attune opens'));
    expect(src, contains('sign out and sign back in with your phone number'));
    expect(src, contains('Nothing is erased'));
  });

  test('explains Where you\'re signed in', () {
    expect(src, contains("id: 'faq_safety_signed_in'"));
    expect(src, contains('Can I see where my account is signed in?'));
    expect(
      src,
      contains('it can take up to an hour for another phone to notice'),
    );
  });
}
