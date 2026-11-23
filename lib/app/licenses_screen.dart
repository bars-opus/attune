// lib/features/licenses/oss_licenses_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Spec 2 W8 final client fix (Task 9 M-8): notices the package scan
    // can't find, added before the page reads the registry.
    AppLicenses.register();
    return const LicensePage(
      applicationName: AppConstants.appName,
      applicationVersion: AppConstants.appVersion,
      applicationLegalese: AppConstants.appCopyright,
    );
  }
}

/// Spec 2 W8 final client fix (Task 9 M-8): licence notices for data the
/// app ships or uses that no package carries. DB-IP Lite (the country
/// table dating-device-check reads, CC BY 4.0) asks for this attribution.
/// Added to Flutter's LicenseRegistry once, when the licences page opens
/// (its one reader).
abstract final class AppLicenses {
  static const dbIp =
      'IP geolocation by DB-IP (https://db-ip.com), licensed under CC BY 4.0.\n'
      'https://creativecommons.org/licenses/by/4.0/';

  static bool _registered = false;

  static void register() {
    if (_registered) return;
    _registered = true;
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(['DB-IP'], dbIp);
    });
  }

  /// Tests: the next [register] adds the notices again (after
  /// LicenseRegistry.reset).
  @visibleForTesting
  static void reset() => _registered = false;
}
