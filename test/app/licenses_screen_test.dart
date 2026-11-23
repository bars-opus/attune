// Spec 2 W8 final client fix (Task 9 M-8): DB-IP Lite's CC BY 4.0
// attribution is in the app's licences page (Flutter's LicenseRegistry),
// added when the page opens, once.
import 'package:attune/app/licenses_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<LicenseEntry>> _dbIp() async => [
  for (final entry in await LicenseRegistry.licenses.toList())
    if (entry.packages.contains('DB-IP')) entry,
];

void main() {
  setUp(() {
    LicenseRegistry.reset();
    AppLicenses.reset();
  });
  tearDown(() {
    LicenseRegistry.reset();
    AppLicenses.reset();
  });

  testWidgets('opening the licences page adds DB-IP\'s attribution, once', (
    t,
  ) async {
    expect(await t.runAsync(_dbIp), isEmpty);
    await t.pumpWidget(const MaterialApp(home: LicensesScreen()));
    await t.pumpWidget(const MaterialApp(home: LicensesScreen(key: Key('b'))));
    final entries = (await t.runAsync(_dbIp))!;
    expect(entries, hasLength(1));
    final text = entries.single.paragraphs.map((p) => p.text).join('\n');
    expect(
      text,
      contains(
        'IP geolocation by DB-IP (https://db-ip.com), licensed under CC BY '
        '4.0.',
      ),
    );
    expect(text, contains('https://creativecommons.org/licenses/by/4.0/'));
    await t.pumpWidget(const SizedBox());
  });
}
