// Spec 2: the quick-exit target is mounted once, in the root shell; no
// screen mounts its own any more; Android leaves through finishAndRemoveTask;
// the PIN and the flag never leave the phone in a backup.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the root shell mounts the zone; HomeScreen no longer does', () {
    expect(
      File('lib/app/app_shell.dart').readAsStringSync(),
      contains('QuickExitZone('),
    );
    expect(File('lib/app/app.dart').readAsStringSync(), contains('appShell('));
    expect(
      File('lib/home/home_screen.dart').readAsStringSync(),
      isNot(contains('TripleTapDetector(')),
    );
  });

  test('Android removes the task through the audited channel', () {
    final kt =
        File(
          'android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt',
        ).readAsStringSync();
    expect(kt, contains('"attune/safety"'));
    expect(kt, contains('finishAndRemoveTask()'));
    final svc =
        File(
          'lib/features/safety/domain/services/quick_exit_service.dart',
        ).readAsStringSync();
    expect(svc, contains("MethodChannel('attune/safety')"));
    expect(svc, contains("'finishAndRemoveTask'"));
  });

  test('iOS covers the app switcher natively', () {
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('willResignActiveNotification'));
    expect(swift, contains('didBecomeActiveNotification'));
  });

  test('activation sends nothing: no network or analytics in the service', () {
    final svc =
        File(
          'lib/features/safety/domain/services/quick_exit_service.dart',
        ).readAsStringSync();
    for (final banned in [
      'http',
      'Supabase',
      'analytics',
      'debugPrint',
      'log(',
    ]) {
      expect(svc.contains(banned), isFalse, reason: banned);
    }
  });

  test('the keystore files are excluded from Android backups (review C2)', () {
    for (final f in [
      'android/app/src/main/res/xml/backup_rules.xml',
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ]) {
      final xml = File(f).readAsStringSync();
      expect(xml, contains('FlutterSecureStorage.xml'), reason: f);
      expect(xml, contains('FlutterSecureKeyStorage.xml'), reason: f);
      expect(xml, contains('attune_safety.xml'), reason: f);
    }
  });
}
