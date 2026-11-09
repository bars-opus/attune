// Spec 2 W3b: every name_key the config can send (W1b's regions and sides,
// W3b's faiths and denominations) has a name in the app, and it is that
// key's own English text (T5 fix round 1, M-3).
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every seeded and published name_key resolves', () {
    final loc = AppLocalizationsEn();
    final sql = [
      'supabase/migrations/20261106130000_dating_v2_country_config.sql',
      'supabase/migrations/20261107160000_dating_v2_setup_lists.sql',
    ].map((p) => File(p).readAsStringSync()).join('\n');
    final keys =
        RegExp(r'"name_key": "(dating_[a-z_]+)"')
            .allMatches(sql)
            .map((m) => m.group(1)!)
            .where((k) => !k.startsWith('dating_id_'))
            .toSet();
    expect(keys.length, 51);
    final arb =
        jsonDecode(File('lib/i10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    for (final key in keys) {
      expect(arb[key], isA<String>(), reason: key);
      expect(datingListName(loc, key), arb[key], reason: key);
    }
  });
}
