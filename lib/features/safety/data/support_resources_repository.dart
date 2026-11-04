import 'dart:async';
import 'dart:convert';

/// Spec 1 W7a (§4.2, §4.3 W7a): the support directory, by country.
///
/// The server's `get_support_resources` is read first; the catalogue the app
/// bundles (`assets/support_resources/catalogue.json`, the same file the
/// server is loaded from) answers when the server can't, or has nothing
/// loaded, so the screen is never empty offline. [SupportCatalogue.forCountry]
/// applies the server's rule exactly: active rows for the country plus
/// anywhere (`XX`), emergency first, then the country's own rows, then
/// `sort_order`, then name.
enum SupportCategory {
  emergency('emergency'),
  dv('dv'),
  crisis('crisis'),
  sexualAssault('sexual_assault'),
  sextortion('sextortion'),
  childSafety('child_safety'),
  youth('youth'),
  lgbtqLegal('lgbtq_legal'),
  grief('grief'),
  perinatal('perinatal'),
  addiction('addiction'),
  financialControl('financial_control');

  const SupportCategory(this.wire);

  final String wire;

  static SupportCategory? fromWire(Object? value) {
    for (final c in values) {
      if (c.wire == value) return c;
    }
    return null;
  }
}

/// `XX`: anywhere in the world.
const supportAnywhere = 'XX';

/// The international helpline directory: the fallback when a country has
/// no checked list and the catalogue offers no link of its own.
const supportDirectoryUrl = 'https://findahelpline.com';

class SupportResource {
  const SupportResource({
    required this.id,
    required this.countryCode,
    required this.category,
    required this.name,
    this.description,
    this.phone,
    this.sms,
    this.whatsapp,
    this.url,
    this.hours,
    this.languages = const [],
    this.isPolice = false,
    this.sortOrder = 100,
  });

  final String id;
  final String countryCode;
  final SupportCategory category;
  final String name;
  final String? description;
  final String? phone;
  final String? sms;
  final String? whatsapp;
  final String? url;
  final String? hours;
  final List<String> languages;
  final bool isPolice;

  /// From the bundled catalogue only: a server answer carries no
  /// `sort_order` (this is 100 there) and arrives ordered, so never re-sort
  /// one (batch-1 review M5).
  final int sortOrder;

  bool get isAnywhere => countryCode == supportAnywhere;

  /// A row this build can't show (an unknown category, no name, no way to
  /// reach anyone) is null and left out, never shown half-formed.
  static SupportResource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final category = SupportCategory.fromWire(raw['category']);
    final id = raw['id'];
    final country = raw['country_code'];
    final name = raw['name'];
    if (category == null ||
        id is! String ||
        country is! String ||
        name is! String ||
        name.trim().isEmpty) {
      return null;
    }
    String? text(String key) {
      final value = raw[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final url = text('url');
    final resource = SupportResource(
      id: id,
      countryCode: country,
      category: category,
      name: name.trim(),
      description: text('description'),
      phone: text('phone'),
      sms: text('sms'),
      whatsapp: text('whatsapp'),
      url: url != null && url.startsWith('https://') ? url : null,
      hours: text('hours'),
      languages: [
        for (final l in (raw['languages'] as List?) ?? const [])
          if (l is String) l,
      ],
      isPolice: raw['is_police'] == true,
      sortOrder: raw['sort_order'] is int ? raw['sort_order'] as int : 100,
    );
    final reachable =
        resource.phone != null ||
        resource.sms != null ||
        resource.whatsapp != null ||
        resource.url != null;
    return reachable ? resource : null;
  }
}

class SupportResources {
  const SupportResources({
    required this.country,
    required this.countrySupported,
    required this.catalogueVersion,
    required this.resources,
    required this.fromServer,
  });

  /// The normalised country asked about, or null (none, or not a country).
  final String? country;
  final bool countrySupported;
  final String? catalogueVersion;
  final List<SupportResource> resources;

  /// False when the bundled catalogue answered.
  final bool fromServer;

  List<SupportResource> get emergency => [
    for (final r in resources)
      if (r.category == SupportCategory.emergency) r,
  ];

  List<SupportResource> inCategory(SupportCategory category) => [
    for (final r in resources)
      if (r.category == category && !r.isAnywhere) r,
  ];

  List<SupportResource> get anywhere => [
    for (final r in resources)
      if (r.isAnywhere && r.category != SupportCategory.emergency) r,
  ];

  /// Where "Find a helpline" goes: the first anywhere entry with a link,
  /// else the international directory.
  String get directoryUrl {
    for (final r in resources) {
      if (r.isAnywhere && r.url != null) return r.url!;
    }
    return supportDirectoryUrl;
  }

  factory SupportResources.fromServer(Map<String, dynamic> json) =>
      SupportResources(
        country: json['country'] is String ? json['country'] as String : null,
        countrySupported: json['country_supported'] == true,
        catalogueVersion:
            json['catalogue_version'] is String
                ? json['catalogue_version'] as String
                : null,
        resources: [
          for (final raw in (json['resources'] as List?) ?? const [])
            if (SupportResource.fromJson(raw) case final r?) r,
        ],
        fromServer: true,
      );
}

/// get_support_resources' country rule: two letters, upper-cased, never XX.
String? normaliseSupportCountry(String? raw) {
  final code = (raw ?? '').trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code) || code == supportAnywhere) {
    return null;
  }
  return code;
}

/// The bundled catalogue.
class SupportCatalogue {
  const SupportCatalogue({required this.version, required this.entries});

  final String version;
  final List<SupportResource> entries;

  static SupportCatalogue parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return SupportCatalogue(
      version: json['catalogue_version'] as String,
      entries: [
        for (final raw in json['resources'] as List)
          if (SupportResource.fromJson(raw) case final r?) r,
      ],
    );
  }

  SupportResources forCountry(String? rawCountry) {
    final country = normaliseSupportCountry(rawCountry);
    final picked = [
      for (final r in entries)
        if (r.countryCode == country || r.isAnywhere) r,
    ];
    int rank(bool b) => b ? 1 : 0;
    picked.sort((a, b) {
      for (final c in [
        rank(a.category != SupportCategory.emergency) -
            rank(b.category != SupportCategory.emergency),
        rank(a.isAnywhere) - rank(b.isAnywhere),
        a.sortOrder - b.sortOrder,
        // Code-unit order, as the server's COLLATE "C" (PF-M3).
        a.name.compareTo(b.name),
        a.id.compareTo(b.id),
      ]) {
        if (c != 0) return c;
      }
      return 0;
    });
    return SupportResources(
      country: country,
      countrySupported: picked.any((r) => r.countryCode == country),
      catalogueVersion: version,
      resources: picked,
      fromServer: false,
    );
  }
}

/// What a phone dials for [phone] as printed: the leading +, the digits,
/// and letters as the keypad has them ("800-799-SAFE (7233)" dials
/// 8007997233). A bracketed part is a spelled-out repeat and is dropped
/// when letters stand outside it; a "(0)" after a country code is the
/// domestic trunk digit and is never dialled with the +.
String supportDialString(String phone) {
  var source = phone.trim();
  if (source.startsWith('+')) source = source.replaceAll('(0)', '');
  final outside = source.replaceAll(RegExp(r'\([^)]*\)'), '');
  if (RegExp(r'[A-Za-z]').hasMatch(outside)) source = outside;
  const keypad = {
    'ABC': '2', 'DEF': '3', 'GHI': '4', 'JKL': '5', //
    'MNO': '6', 'PQRS': '7', 'TUV': '8', 'WXYZ': '9',
  };
  final out = StringBuffer();
  for (final ch in source.trim().split('')) {
    if (ch == '+' && out.isEmpty) {
      out.write(ch);
    } else if (RegExp(r'[0-9]').hasMatch(ch)) {
      out.write(ch);
    } else if (RegExp(r'[A-Za-z]').hasMatch(ch)) {
      final upper = ch.toUpperCase();
      for (final entry in keypad.entries) {
        if (entry.key.contains(upper)) out.write(entry.value);
      }
    }
  }
  return out.toString();
}

typedef SupportRpc =
    Future<Object?> Function(String fn, Map<String, dynamic> params);

class SupportResourcesRepository {
  SupportResourcesRepository({
    required SupportRpc rpc,
    required Future<String> Function() loadBundled,
    this.timeout = defaultTimeout,
  }) : _rpc = rpc,
       _loadBundled = loadBundled;

  final SupportRpc _rpc;
  final Future<String> Function() _loadBundled;
  SupportCatalogue? _bundled;

  /// 4 s (final review M-6): on a bad connection the bundled list shows
  /// after at most this long.
  static const defaultTimeout = Duration(seconds: 4);

  /// How long the server gets before the bundled catalogue answers.
  final Duration timeout;

  Future<SupportCatalogue> bundled() async =>
      _bundled ??= SupportCatalogue.parse(await _loadBundled());

  /// The server's answer, or the bundled catalogue's when the server fails,
  /// times out, or has no rows at all (a project the catalogue was never
  /// loaded into).
  Future<SupportResources> load(String? country) async {
    try {
      final data = await _rpc('get_support_resources', {
        'p_country': normaliseSupportCountry(country),
      }).timeout(timeout);
      final answer = SupportResources.fromServer(
        Map<String, dynamic>.from(data as Map),
      );
      if (answer.resources.isNotEmpty) return answer;
    } catch (_) {
      // Offline, refused or malformed: the bundled catalogue answers.
    }
    return (await bundled()).forCountry(country);
  }
}
