import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps local-only files out of the iOS device and iCloud backup.
///
/// Application Support is backed up on iOS unless a file or folder sets
/// NSURLIsExcludedFromBackupKey; the Runner (AppDelegate, channel
/// `attune/backup_exclusion`) sets it. Android needs no call: its
/// backup_rules.xml / data_extraction_rules.xml exclude the same paths.
///
/// Best-effort by design: it never throws, and a failure only means the
/// item may be backed up (it is retried on the next call).
class BackupExclusion {
  const BackupExclusion._();

  static const MethodChannel channel = MethodChannel('attune/backup_exclusion');

  /// Test seam for the platform check.
  @visibleForTesting
  static bool? debugIsIOS;

  static final Set<String> _excluded = {};

  /// Excludes [path] (a file or folder that already exists) from backup.
  /// With [once], a path already excluded this launch is not sent again —
  /// for folders, which keep the flag; a file that may be deleted and
  /// recreated (the chat cache store) passes `once: false`.
  static Future<void> exclude(String path, {bool once = true}) async {
    if (!(debugIsIOS ?? Platform.isIOS)) return;
    if (once && _excluded.contains(path)) return;
    try {
      await channel.invokeMethod<void>('excludeFromBackup', path);
      _excluded.add(path);
    } catch (_) {
      // Left out of the set: the next call tries again.
    }
  }

  @visibleForTesting
  static void debugReset() => _excluded.clear();
}
