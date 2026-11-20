// Spec 2 W5b Task 6 fix round 1 (T6 review M-6): inside Dating, raw
// package:http is imported only by the Dating-scoped client itself (which
// wraps it to add the device header) and by the Today providers (which
// fetch 60-second signed storage URLs: no session, no device header). Any
// other Dating call to the backend goes through datingSupabaseClient, so
// it can never skip x-attune-device.
//
// W5 final fix (M-5, T6 R1-2): an `export` of package:http counts as a use,
// and dart:io's own HttpClient is allowed nowhere in Dating (it would skip
// the header as surely).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('package:http is imported only where Dating allows it', () {
    const allowed = {
      'lib/features/dating/data/dating_supabase_client.dart',
      'lib/features/dating/today/dating_today_providers.dart',
    };
    final http = RegExp(r'''^\s*(import|export)\s+['"]package:http/''');
    final hits = <String>{};
    for (final f
        in Directory(
          'lib/features/dating',
        ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.readAsLinesSync().any(http.hasMatch)) hits.add(f.path);
    }
    expect(hits, allowed);
  });

  test("dart:io's HttpClient is used nowhere in Dating", () {
    final client = RegExp(r'\bHttpClient\b');
    final hits = <String>{};
    for (final f
        in Directory(
          'lib/features/dating',
        ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final code = [
        for (final line in f.readAsLinesSync())
          if (!line.trimLeft().startsWith('//')) line,
      ];
      if (code.any(client.hasMatch)) hits.add(f.path);
    }
    expect(hits, isEmpty);
  });
}
