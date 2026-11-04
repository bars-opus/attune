// Spec 1 W7a (§4.3 W7a): the support directory on the phone. The bundled
// catalogue answers with the server's own rule (the same fixture rows as
// support_resources_contracts.sql section B give the same order); the
// server is read first and the bundle answers when it fails, times out or
// is empty; numbers dial as printed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _entry(
  String n,
  String country,
  String category,
  String name, {
  int sort = 100,
  String? url,
  String? phone = '0800 000 000',
}) => {
  'id': '5f7a0000-0000-0000-0000-0000000000$n',
  'country_code': country,
  'category': category,
  'name': name,
  'phone': phone,
  'url': url,
  'languages': ['en'],
  'is_police': category == 'emergency',
  'sort_order': sort,
  'verified_at': '2026-11-03',
  'verified_by': 'test fixture',
};

final _fixture = jsonEncode({
  'catalogue_version': 'fixture-1',
  'resources': [
    _entry('01', 'GH', 'dv', 'GH DV line', sort: 10),
    _entry('02', 'GH', 'emergency', 'GH emergency', sort: 90),
    _entry('03', 'GH', 'crisis', 'GH crisis line', sort: 5),
    _entry(
      '04',
      'XX',
      'crisis',
      'Anywhere directory',
      sort: 1,
      url: 'https://findahelpline.com',
      phone: null,
    ),
    _entry('05', 'GB', 'dv', 'GB DV line', sort: 1),
    _entry('06', 'GH', 'astrology', 'Unknown category'),
    _entry('07', 'GH', 'dv', 'No way to reach', phone: null),
    // Same sort_order, mixed case: names sort bytewise, as the server's
    // COLLATE "C" does (pre-flight PF-M3), so upper case comes first.
    _entry('08', 'GH', 'youth', 'GH apple line', sort: 50),
    _entry('09', 'GH', 'youth', 'GH Zulu line', sort: 50),
  ],
});

SupportResourcesRepository _repo(
  Future<Object?> Function() server, {
  List<String>? calls,
}) => SupportResourcesRepository(
  rpc: (fn, params) {
    calls?.add('$fn ${jsonEncode(params)}');
    return server();
  },
  loadBundled: () async => _fixture,
);

void main() {
  test(
    'the bundle answers with the server rule (contract section B order)',
    () {
      final gh = SupportCatalogue.parse(_fixture).forCountry(' gh ');
      expect(
        [for (final r in gh.resources) r.name],
        [
          'GH emergency',
          'GH crisis line',
          'GH DV line',
          'GH Zulu line',
          'GH apple line',
          'Anywhere directory',
        ],
      );
      expect(gh.country, 'GH');
      expect(gh.countrySupported, isTrue);
      expect(gh.catalogueVersion, 'fixture-1');
      expect(gh.fromServer, isFalse);
      expect([for (final r in gh.emergency) r.name], ['GH emergency']);
      expect([for (final r in gh.anywhere) r.name], ['Anywhere directory']);
    },
  );

  test('no list for a country, or no country: anywhere only, unsupported', () {
    final catalogue = SupportCatalogue.parse(_fixture);
    for (final country in ['ZZ', 'xx', '', 'Ghana', null]) {
      final answer = catalogue.forCountry(country);
      expect(answer.countrySupported, isFalse, reason: '$country');
      expect(
        [for (final r in answer.resources) r.countryCode],
        ['XX'],
        reason: '$country',
      );
      expect(answer.directoryUrl, 'https://findahelpline.com');
    }
  });

  test('server first; its answer is used as it comes', () async {
    final calls = <String>[];
    final answer = await _repo(
      () async => {
        'country': 'GB',
        'country_supported': true,
        'catalogue_version': 'server-7',
        'resources': [_entry('05', 'GB', 'dv', 'GB DV line from server')],
      },
      calls: calls,
    ).load('gb');
    expect(calls, ['get_support_resources {"p_country":"GB"}']);
    expect(answer.fromServer, isTrue);
    expect(answer.catalogueVersion, 'server-7');
    expect(answer.resources.single.name, 'GB DV line from server');
  });

  test('a failing server falls back to the bundle', () async {
    final answer = await _repo(
      () async => throw const SocketException('x'),
    ).load('GH');
    expect(answer.fromServer, isFalse);
    expect(answer.resources.first.name, 'GH emergency');
  });

  test('a server with nothing loaded falls back to the bundle', () async {
    final answer = await _repo(
      () async => {
        'country': 'GH',
        'country_supported': false,
        'catalogue_version': null,
        'resources': <Object>[],
      },
    ).load('GH');
    expect(answer.fromServer, isFalse);
    expect(answer.countrySupported, isTrue);
  });

  test('a malformed answer falls back to the bundle', () async {
    final answer = await _repo(() async => 'not a map').load('GH');
    expect(answer.fromServer, isFalse);
  });

  test('a slow server falls back to the bundle after the timeout', () async {
    final never = Completer<Object?>();
    final answer = await SupportResourcesRepository(
      rpc: (_, __) => never.future,
      loadBundled: () async => _fixture,
      timeout: const Duration(milliseconds: 50),
    ).load('GH');
    expect(answer.fromServer, isFalse);
    // Final review M-6: a person on a bad connection waits at most 4 s
    // before the bundled list shows.
    expect(
      SupportResourcesRepository.defaultTimeout,
      const Duration(seconds: 4),
    );
  });

  // Final review M-6: the bundle's answer is not kept for the rest of the
  // run. Once the screen is closed, the next open asks the server again.
  test('a bundle answer is not kept: the next open asks the server', () async {
    var online = false;
    final container = ProviderContainer(
      overrides: [
        supportResourcesRepositoryProvider.overrideWithValue(
          _repo(() async {
            if (!online) throw const SocketException('offline');
            return {
              'country': 'GH',
              'country_supported': true,
              'catalogue_version': 'server-8',
              'resources': [_entry('01', 'GH', 'dv', 'GH DV line from server')],
            };
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    var open = container.listen(supportResourcesProvider('GH'), (_, __) {});
    final first = await container.read(supportResourcesProvider('GH').future);
    expect(first.fromServer, isFalse);
    // The screen closes; the connection comes back; the screen opens again.
    open.close();
    await container.pump();
    online = true;
    open = container.listen(supportResourcesProvider('GH'), (_, __) {});
    addTearDown(open.close);
    final second = await container.read(supportResourcesProvider('GH').future);
    expect(second.fromServer, isTrue);
    expect(second.catalogueVersion, 'server-8');
  });

  test('rows this build cannot show are left out, never half shown', () {
    final names = [
      for (final r in SupportCatalogue.parse(_fixture).entries) r.name,
    ];
    expect(names, isNot(contains('Unknown category')));
    expect(names, isNot(contains('No way to reach')));
  });

  test('numbers dial as printed', () {
    expect(supportDialString('055 100 0900'), '0551000900');
    expect(supportDialString('800-799-SAFE (7233)'), '8007997233');
    expect(supportDialString('0808 2000 247'), '08082000247');
    expect(supportDialString('+44 (0)20 0000 0000'), '+442000000000');
    expect(supportDialString('116 123'), '116123');
  });

  test('Find a helpline goes to the catalogue link, else the directory', () {
    String catalogue(List<Map<String, Object?>> rows) =>
        jsonEncode({'catalogue_version': 'fixture-d', 'resources': rows});
    final own = SupportCatalogue.parse(
      catalogue([
        _entry('01', 'GH', 'dv', 'GH DV line'),
        _entry(
          '04',
          'XX',
          'crisis',
          'Anywhere list',
          url: 'https://example.org/helplines',
          phone: null,
        ),
      ]),
    );
    expect(own.forCountry('ZZ').directoryUrl, 'https://example.org/helplines');
    expect(own.forCountry('GH').directoryUrl, 'https://example.org/helplines');
    final none = SupportCatalogue.parse(
      catalogue([
        _entry('01', 'GH', 'dv', 'GH DV line'),
        _entry('04', 'XX', 'crisis', 'Anywhere phone only'),
      ]),
    );
    expect(none.forCountry('GH').directoryUrl, supportDirectoryUrl);
  });

  test('emergency, a category and anywhere each pick their own rows', () {
    final answer = SupportCatalogue.parse(
      jsonEncode({
        'catalogue_version': 'fixture-c',
        'resources': [
          _entry('01', 'GH', 'dv', 'GH DV line', sort: 10),
          _entry('02', 'GH', 'emergency', 'GH emergency'),
          _entry('03', 'XX', 'emergency', 'Anywhere emergency'),
          _entry('04', 'XX', 'dv', 'Anywhere DV line'),
          _entry('05', 'GH', 'crisis', 'GH crisis line'),
          _entry(
            '06',
            'GH',
            'dv',
            'GH plain http',
            sort: 20,
            url: 'http://x.org',
          ),
        ],
      }),
    ).forCountry('GH');
    expect(
      [for (final r in answer.emergency) r.name],
      ['GH emergency', 'Anywhere emergency'],
    );
    expect(
      [for (final r in answer.inCategory(SupportCategory.dv)) r.name],
      ['GH DV line', 'GH plain http'],
    );
    expect([for (final r in answer.anywhere) r.name], ['Anywhere DV line']);
    final http = answer.resources.singleWhere((r) => r.name == 'GH plain http');
    expect(http.url, isNull);
    expect(http.phone, '0800 000 000');
  });

  testWidgets('the app bundles the catalogue (pubspec assets)', (tester) async {
    final bundled = await rootBundle.loadString(
      'assets/support_resources/catalogue.json',
    );
    expect(
      bundled,
      File('assets/support_resources/catalogue.json').readAsStringSync(),
    );
  });

  test('the shipped catalogue parses whole and has its directory', () {
    final source =
        File('assets/support_resources/catalogue.json').readAsStringSync();
    final raw = (jsonDecode(source) as Map)['resources'] as List;
    final catalogue = SupportCatalogue.parse(source);
    expect(catalogue.entries, hasLength(raw.length));
    expect(
      catalogue.forCountry('ZZ').directoryUrl,
      'https://findahelpline.com',
    );
  });
}
