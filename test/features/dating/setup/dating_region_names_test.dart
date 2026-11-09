// Spec 2 W3a: every region and side the country config can send has a name
// in the app (W1b's name_key values); an unknown code reads as itself.
import 'dart:io';

import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final loc = AppLocalizationsEn();
  test('every seeded region and side key resolves', () {
    final seed =
        File(
          'supabase/migrations/20261106130000_dating_v2_country_config.sql',
        ).readAsStringSync();
    final keys =
        RegExp(
          r'"name_key": "(dating_(?:region|side)_[a-z_]+)"',
        ).allMatches(seed).map((m) => m.group(1)!).toSet();
    expect(keys.length, 32);
    for (final key in keys) {
      expect(datingListName(loc, key), isNotNull, reason: key);
    }
  });

  test('by code: Ghana and the UK; an unknown code reads as its code', () {
    expect(datingRegionName(loc, 'GH', 'AA'), 'Greater Accra');
    expect(datingRegionName(loc, 'gb', 'tli'), 'London');
    expect(datingRegionName(loc, 'GH', 'ZZ'), 'ZZ');
    expect(
      datingRegionList(loc, 'GH', ['AA', 'AH']),
      'Greater Accra and Ashanti',
    );
  });
}
