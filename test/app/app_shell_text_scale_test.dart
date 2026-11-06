// Spec 1 W10a (§5.2): the root shell's text clamp is RootTextScaleClamp with
// the cap from textScaleCapProvider; the fixed 1.0 clamp is gone.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app_shell.dart clamps through RootTextScaleClamp', () {
    final shell = File('lib/app/app_shell.dart').readAsStringSync();
    expect(shell, contains('RootTextScaleClamp('));
    expect(shell, contains('cap: maxTextScale,'));
    expect(shell, isNot(contains('maxScaleFactor: 1.0')));
  });

  test('app.dart passes the cap from textScaleCapProvider', () {
    final app = File('lib/app/app.dart').readAsStringSync();
    expect(app, contains('ref.watch(textScaleCapProvider)'));
    expect(app, contains('maxTextScale: textScaleCap,'));
  });
}
