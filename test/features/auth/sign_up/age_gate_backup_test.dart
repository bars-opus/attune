// Spec 1 W2a (§3.2, §3.6, review F-5): the guest's birth year never leaves
// the phone in a backup; the under-18 block does, so it usually survives a
// reinstall.
import 'dart:io';

import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _sections(String path) {
  final xml = File(path).readAsStringSync();
  if (!path.contains('extraction')) return [xml];
  return [
    xml.substring(
      xml.indexOf('<cloud-backup>'),
      xml.indexOf('</cloud-backup>'),
    ),
    xml.substring(
      xml.indexOf('<device-transfer>'),
      xml.indexOf('</device-transfer>'),
    ),
  ];
}

void main() {
  const files = [
    'android/app/src/main/res/xml/backup_rules.xml',
    'android/app/src/main/res/xml/data_extraction_rules.xml',
  ];

  test('the age-gate keystore file is excluded everywhere', () {
    for (final path in files) {
      for (final section in _sections(path)) {
        expect(
          section,
          contains(
            '<exclude domain="sharedpref" path="${AgeGateStore.keystoreFile}.xml" />',
          ),
          reason: path,
        );
      }
    }
  });

  test('the default prefs file, which holds the block, is never excluded', () {
    for (final path in files) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('FlutterSharedPreferences')),
      );
    }
  });
}
