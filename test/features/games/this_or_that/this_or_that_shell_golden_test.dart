import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../platform/support/game_test_support.dart';
import 'support/shell_screens.dart';

/// This or That's screens in the games shell, on a phone, in a LIGHT app.
///
/// For looking at: open the PNGs when they are regenerated. A light app is
/// the case that shows a screen which forgot the games are dark.
void main() {
  // Once for the file: loading the fonts inside each test has hung a file.
  setUpAll(loadGameTestFonts);

  // Text is drawn slightly differently on each operating system; these are
  // compared where they are made. What a machine can check -- ink on the
  // ground and on the orange -- is checked everywhere by the shell test.
  final comparedHere = Platform.isMacOS;

  for (final MapEntry(key: name, value: screen)
      in thisOrThatShellScreens().entries) {
    testWidgets('$name on a phone', (tester) async {
      await pumpShellScreen(tester, screen);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/this_or_that_shell_$name.phone.png'),
      );
    }, skip: !comparedHere);
  }
}
