// Spec 3c (R3c-5): Download my data is always in Settings -> Account, on the
// ended card, and named before anyone seals their side.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  test('the router serves /settings/download-my-data as dataExport', () {
    final src = _read('lib/app/routing/app_router.dart');
    expect(
      src,
      contains("static const String dataExport = DataExportScreen.routeName;"),
    );
    expect(src, contains("name: 'dataExport'"));
    expect(src, contains('const DataExportScreen()'));
  });

  // Settings regrouped (2026-10-18): Privacy & your data, after Where
  // you're signed in.
  test('Settings -> Privacy & your data lists it after Where you\'re signed in', () {
    final src = _read('lib/features/settings/data/settings_data.dart');
    final devices = src.indexOf("id: 'signed_in_devices'");
    final export = src.indexOf("id: 'download_my_data'");
    expect(export, greaterThan(devices));
    expect(src.indexOf("id: 'care'"), greaterThan(export));
    expect(src, contains("routeName: '/settings/download-my-data'"));
  });

  test('the ended card offers it and the seal confirm names it first', () {
    final src = _read(
      'lib/features/relationships/presentation/widgets/relationship_lifecycle_card.dart',
    );
    expect(src, contains("Text('Download what we shared')"));
    expect(
      src,
      contains('Download what you shared first: Settings → Download my data.'),
    );
  });

  test('the manual says what a download holds and what it never does', () {
    final src = _read(
      'lib/app/documentations/user_manual/data/about_attune_docs.dart',
    );
    expect(src, contains("id: 'faq_about_download_data'"));
    expect(src, contains('Can I download my data?'));
    // Insights and readouts are included; the copy must not say otherwise
    // (final review I3).
    expect(src, contains('never anything about safety'));
    expect(src, isNot(contains(r"never includes Attune\'s own analysis")));
  });
}
