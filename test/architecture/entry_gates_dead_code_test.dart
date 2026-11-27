// Entry gates (owner 2026-11-27, fixes 4 and 6): the new sign-in is the
// only one. The legacy onboarding gate, its flow and the EULA sheet are
// gone, and so is every email, OAuth and auth-callback sign-in path. The
// auth_exports.dart barrel (Games-guarded) still exports
// auth_button_config.dart and auth_ui_service.dart, so both files stay and
// compile, inert.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

void main() {
  test('the legacy gate, its flow and the EULA sheet are deleted', () {
    for (final path in [
      'lib/features/onboarding/presentation/screens/onboarding_gate.dart',
      'lib/features/onboarding/presentation/screens/onboarding_flow.dart',
      'lib/features/auth/presentation/eula_gate.dart',
      'lib/features/auth/data/eula_acceptance_service.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('no code in lib/ names them', () {
    final pattern = RegExp(
      r'\b(OnboardingGate|OnboardingFlow|EulaGate|EulaAcceptanceService)\b',
    );
    for (final file in _dartFiles('lib')) {
      final source = file.readAsStringSync();
      // Comments may still tell the history; code may not use them.
      final code = source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(pattern.hasMatch(code), isFalse, reason: file.path);
    }
  });

  test('no email, OAuth or auth-callback sign-in is left in lib/', () {
    final pattern = RegExp(
      r'getSessionFromUrl|signInWithOAuth|signInWithIdToken|'
      r'signInWithPassword|signInWithGoogle|signInWithApple|'
      r'signInWithEmail|signUpWithEmail|resetPasswordForEmail|'
      r'auth\.signUp\(',
    );
    for (final file in _dartFiles('lib')) {
      expect(
        pattern.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: file.path,
      );
    }
  });

  test('the barrel still exports both auth files, and they exist', () {
    final barrel =
        File('lib/features/auth/utility/auth_exports.dart').readAsStringSync();
    for (final path in [
      'features/auth/log_in/presentation/widgets/auth_button_config.dart',
      'features/auth/services/auth_ui_service.dart',
    ]) {
      expect(barrel, contains("export 'package:attune/$path';"));
      expect(File('lib/$path').existsSync(), isTrue, reason: path);
    }
  });
}
