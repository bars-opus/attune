import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every permission the app relies on is declared', () {
    // Android SILENTLY ignores an undeclared permission — no error, no
    // log. HapticFeedback calls simply never landed, which presented as
    // "haptics work sometimes" and cost several rounds of chasing Dart
    // state that was never the problem.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    const required = {
      'VIBRATE': 'HapticFeedback throughout the app',
      'RECORD_AUDIO': 'voice messages and streak audio',
      'CAMERA': 'streak and ephemeral capture',
      'INTERNET': 'everything',
    };

    for (final entry in required.entries) {
      expect(
        manifest,
        contains('android.permission.${entry.key}'),
        reason: '${entry.key} is needed for ${entry.value}',
      );
    }
  });

  test('backups never carry staged chat photos or their upload files', () {
    // Chat stages picks and prepared uploads in Application Support
    // (filesDir on Android) so a queued photo survives a cache purge; that
    // folder is backed up unless excluded. Same rule as the chat cache.
    for (final path in [
      'android/app/src/main/res/xml/backup_rules.xml',
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ]) {
      final xml = File(path).readAsStringSync();
      final sections =
          path.contains('extraction')
              ? [
                xml.substring(
                  xml.indexOf('<cloud-backup>'),
                  xml.indexOf('</cloud-backup>'),
                ),
                xml.substring(
                  xml.indexOf('<device-transfer>'),
                  xml.indexOf('</device-transfer>'),
                ),
              ]
              : [xml];
      for (final section in sections) {
        for (final folder in ['chat_picks/', 'chat_prepared/']) {
          expect(
            section,
            contains('<exclude domain="file" path="$folder" />'),
            reason: '$path must exclude $folder',
          );
        }
      }
    }
  });

  test('backups never carry cached voice/video bytes', () {
    // ChatMediaCache needs no exclusion only because everything it writes
    // (files, its database, its ownership index) sits in the OS cache
    // directory, which iOS and Android never back up. The database would
    // default to Application Support (backed up), so it is placed
    // explicitly. Behaviour: chat_media_cache_test.dart, "everything lives
    // in the OS cache directory".
    final source = File(
      'lib/features/chat/domain/services/chat_media_cache.dart',
    ).readAsStringSync();
    expect(source, contains('getTemporaryDirectory()'));
    expect(source, contains('path: at.database'));
    for (final backedUp in [
      'getApplicationSupportDirectory',
      'getApplicationDocumentsDirectory',
      'getLibraryDirectory',
    ]) {
      expect(
        source.contains(backedUp),
        isFalse,
        reason: 'ChatMediaCache must not write to $backedUp (backed up); '
            'if it must, exclude it in backup_rules.xml, '
            'data_extraction_rules.xml (both sections) and BackupExclusion',
      );
    }
  });
}
