import 'dart:io';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BorderWidthTokens.md is a real width', () {
    // It shipped as `static var md;` -- no type, no value -- so it
    // evaluated to null and every use threw "type 'Null' is not a subtype
    // of type 'double'" the moment a selected border rendered. It broke
    // This or That's question screen and forum side selection.
    expect(BorderWidthTokens.md, isA<double>());
    expect(BorderWidthTokens.md, greaterThan(0));
  });

  test('no design token is declared without a value', () {
    // The reason the analyzer stayed silent: `var` with no initialiser is
    // dynamic, so both call sites type-checked fine and failed only at
    // runtime. A token file is exactly where this hides -- the values are
    // read everywhere and written once.
    // Comment lines are stripped first: the fix's own doc comment quotes
    // the broken declaration it replaced, so a whole-file search finds
    // the warning against the pattern rather than the pattern.
    final source = File('lib/app/theme/design_tokens.dart')
        .readAsStringSync()
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    final uninitialised = RegExp(
      r'static\s+(var|dynamic)\s+\w+\s*;',
    ).allMatches(source).map((m) => m.group(0)).toList();

    expect(
      uninitialised,
      isEmpty,
      reason:
          'these evaluate to null and throw wherever they are used: '
          '$uninitialised',
    );
  });
}
