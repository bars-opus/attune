// Spec 1 W7a (§8 W7a): the bundled support catalogue is never shipped
// stale. Every entry for a Tier A country (Ghana, the UK, the US, Canada)
// must have been checked within 90 days, and within 7 days on a release
// tag (GitHub sets GITHUB_REF_TYPE=tag for a tag push). There must always
// be an anywhere (XX) entry with a link, the fallback for every country
// without a checked list. A wrong crisis number is a safety harm, so the
// rule is applied to the shipped file itself (last test); the rule is
// proven on fixtures first.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const tierA = {'GH', 'GB', 'US', 'CA'};

/// Everything wrong with [catalogue] on [today]; empty when it may ship.
List<String> catalogueProblems(
  Map<String, dynamic> catalogue, {
  required DateTime today,
  required bool releaseTag,
}) {
  final maxDays = releaseTag ? 7 : 90;
  final day = DateTime.utc(today.year, today.month, today.day);
  final problems = <String>[];
  final entries = (catalogue['resources'] as List).cast<Map>();
  for (final e in entries) {
    final country = e['country_code'];
    if (!tierA.contains(country)) continue;
    final checked = DateTime.tryParse('${e['verified_at']}');
    if (checked == null) {
      problems.add('$country ${e['name']}: no verified_at');
      continue;
    }
    final age =
        day
            .difference(DateTime.utc(checked.year, checked.month, checked.day))
            .inDays;
    if (age < 0) {
      problems.add(
        '$country ${e['name']}: verified_at ${e['verified_at']} is in the future',
      );
      continue;
    }
    if (age > maxDays) {
      problems.add(
        '$country ${e['name']}: checked $age days ago (at most $maxDays)',
      );
    }
  }
  final directory = entries.any(
    (e) =>
        e['country_code'] == 'XX' && '${e['url'] ?? ''}'.startsWith('https://'),
  );
  if (!directory) problems.add('no anywhere (XX) entry with a link');
  return problems;
}

Map<String, dynamic> _catalogue(List<Map<String, Object?>> rows) => {
  'catalogue_version': 'fixture',
  'resources': rows,
};

Map<String, Object?> _row(String country, String verifiedAt, {String? url}) => {
  'country_code': country,
  'name': '$country line',
  'url': url,
  'verified_at': verifiedAt,
};

final _directory = _row('XX', '2020-01-01', url: 'https://findahelpline.com');

void main() {
  final today = DateTime.utc(2026, 11, 3);

  test('90 days ordinarily; Tier A only', () {
    final fresh = _catalogue([
      _row('GH', '2026-08-05'),
      _row('KE', '2020-01-01'),
      _directory,
    ]);
    expect(catalogueProblems(fresh, today: today, releaseTag: false), isEmpty);
    final stale = _catalogue([_row('GB', '2026-08-04'), _directory]);
    expect(catalogueProblems(stale, today: today, releaseTag: false), [
      'GB GB line: checked 91 days ago (at most 90)',
    ]);
  });

  test('a check dated in the future is a problem (a year typo)', () {
    final future = _catalogue([_row('GH', '2026-11-04'), _directory]);
    for (final releaseTag in [false, true]) {
      expect(catalogueProblems(future, today: today, releaseTag: releaseTag), [
        'GH GH line: verified_at 2026-11-04 is in the future',
      ]);
    }
  });

  test('7 days on a release tag', () {
    final week = _catalogue([_row('US', '2026-10-27'), _directory]);
    expect(catalogueProblems(week, today: today, releaseTag: true), isEmpty);
    final eight = _catalogue([_row('CA', '2026-10-26'), _directory]);
    expect(catalogueProblems(eight, today: today, releaseTag: true), [
      'CA CA line: checked 8 days ago (at most 7)',
    ]);
  });

  test('there is always somewhere to go', () {
    expect(
      catalogueProblems(
        _catalogue([_row('GH', '2026-11-03')]),
        today: today,
        releaseTag: false,
      ),
      ['no anywhere (XX) entry with a link'],
    );
  });

  test('the shipped catalogue may ship today', () {
    final catalogue =
        jsonDecode(
              File(
                'assets/support_resources/catalogue.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final releaseTag = Platform.environment['GITHUB_REF_TYPE'] == 'tag';
    expect(
      catalogueProblems(
        catalogue,
        today: DateTime.now().toUtc(),
        releaseTag: releaseTag,
      ),
      isEmpty,
      reason:
          'Re-check these entries with a named reviewer, update verified_at and '
          'verified_by in assets/support_resources/catalogue.json, and load it '
          '(scripts/load_support_resources.sh).',
    );
  });
}
