import 'dart:async';
import 'dart:convert';

import 'package:attune/core/config/env.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The public, pre-auth configuration (Spec 1 §2.5, §4.3 W1c, D15): the
/// effective values of the four flags a signed-out phone needs, the App
/// Store storefronts that read Declared Age Range, and the Dating
/// open-country list (ISO 3166-1 alpha-2, sorted), which comes only through
/// the server seam private.dating_open_countries().
@immutable
class PublicAppConfig {
  const PublicAppConfig({
    required this.flowSignInV2,
    required this.platformAgeSignals,
    required this.supportResourcesV2,
    required this.textScaleV2,
    required this.ageSignalStorefronts,
    required this.datingOpenCountries,
  });

  /// Everything off, nothing listed: what an unreadable config means.
  static const off = PublicAppConfig(
    flowSignInV2: false,
    platformAgeSignals: false,
    supportResourcesV2: false,
    textScaleV2: false,
    ageSignalStorefronts: [],
    datingOpenCountries: [],
  );

  final bool flowSignInV2;
  final bool platformAgeSignals;
  final bool supportResourcesV2;
  final bool textScaleV2;
  final List<String> ageSignalStorefronts;
  final List<String> datingOpenCountries;

  /// Reads get_public_app_config(). Only a literal `true` is on; only
  /// strings are kept from the lists.
  factory PublicAppConfig.fromJson(Map<String, dynamic> json) {
    final flags = json['flags'] is Map ? json['flags'] as Map : const {};
    final config = json['config'] is Map ? json['config'] as Map : const {};
    List<String> strings(Object? value) => [
      if (value is List)
        for (final item in value)
          if (item is String) item,
    ];
    return PublicAppConfig(
      flowSignInV2: flags['flow_signin_v2'] == true,
      platformAgeSignals: flags['platform_age_signals'] == true,
      supportResourcesV2: flags['support_resources_v2'] == true,
      textScaleV2: flags['text_scale_v2'] == true,
      ageSignalStorefronts: strings(config['age_signal_storefronts']),
      datingOpenCountries: strings(config['dating_open_countries']),
    );
  }

  Map<String, dynamic> toJson() => {
    'flags': {
      'flow_signin_v2': flowSignInV2,
      'platform_age_signals': platformAgeSignals,
      'support_resources_v2': supportResourcesV2,
      'text_scale_v2': textScaleV2,
    },
    'config': {
      'age_signal_storefronts': ageSignalStorefronts,
      'dating_open_countries': datingOpenCountries,
    },
  };

  /// Value equality (batch 6 review #3), so a re-read that returns the same
  /// config changes nothing for the providers that select it.
  @override
  bool operator ==(Object other) =>
      other is PublicAppConfig &&
      other.flowSignInV2 == flowSignInV2 &&
      other.platformAgeSignals == platformAgeSignals &&
      other.supportResourcesV2 == supportResourcesV2 &&
      other.textScaleV2 == textScaleV2 &&
      listEquals(other.ageSignalStorefronts, ageSignalStorefronts) &&
      listEquals(other.datingOpenCountries, datingOpenCountries);

  @override
  int get hashCode => Object.hash(
    flowSignInV2,
    platformAgeSignals,
    supportResourcesV2,
    textScaleV2,
    Object.hashAll(ageSignalStorefronts),
    Object.hashAll(datingOpenCountries),
  );
}

/// The one network read, so tests can replace it.
abstract class PublicAppConfigGateway {
  Future<Map<String, dynamic>> fetch();
}

class SupabasePublicAppConfigGateway implements PublicAppConfigGateway {
  SupabasePublicAppConfigGateway(this._client);

  final SupabaseClient _client;

  static const timeout = Duration(seconds: 10);

  @override
  Future<Map<String, dynamic>> fetch() async {
    final data = await _client.rpc('get_public_app_config').timeout(timeout);
    return Map<String, dynamic>.from(data as Map);
  }
}

/// The last answer, for the first frame of the next launch (no network).
///
/// Stored under its own neutral field names, not the server's: no device key
/// or value names Dating (D20, spec §5.5), so the open-country list is
/// `open_countries` here (batch 6 review #1). The flags keep their names.
class PublicAppConfigCache {
  const PublicAppConfigCache(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'attune.public_config.v1';

  PublicAppConfig? read() {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return PublicAppConfig.fromJson({
        'flags': json['flags'],
        'config': {
          'age_signal_storefronts': json['storefronts'],
          'dating_open_countries': json['open_countries'],
        },
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> write(PublicAppConfig config) => _prefs.setString(
    key,
    jsonEncode({
      'flags': config.toJson()['flags'],
      'storefronts': config.ageSignalStorefronts,
      'open_countries': config.datingOpenCountries,
    }),
  );
}

final publicAppConfigGatewayProvider = Provider<PublicAppConfigGateway>(
  (ref) => SupabasePublicAppConfigGateway(Supabase.instance.client),
);

/// The cached copy, read synchronously at first use.
final cachedPublicAppConfigProvider = Provider<PublicAppConfig?>(
  (ref) => PublicAppConfigCache(ref.watch(sharedPreferencesProvider)).read(),
);

/// The live config. A failed read keeps the cached copy, else everything is
/// off. Re-read on resume and on a change of user (FeatureFlagRefresher).
final publicAppConfigProvider = FutureProvider<PublicAppConfig>((ref) async {
  final cache = PublicAppConfigCache(ref.read(sharedPreferencesProvider));
  final PublicAppConfig config;
  try {
    config = PublicAppConfig.fromJson(
      await ref.read(publicAppConfigGatewayProvider).fetch(),
    );
  } catch (error) {
    debugPrint('[public-config] read failed: ${error.runtimeType}');
    return cache.read() ?? PublicAppConfig.off;
  }
  // Fire-and-forget (batch 6 review #2): a failed prefs write never costs
  // the fresh answer; the next good read writes it again.
  unawaited(() async {
    try {
      await cache.write(config);
    } catch (error) {
      debugPrint('[public-config] cache write failed: ${error.runtimeType}');
    }
  }());
  return config;
});

/// flow_signin_v2, effective (the server applies the flag dependencies).
/// Before the first answer: the cached copy, else [Environment.flowV2Default].
final flowSignInV2Provider = Provider<bool>((ref) {
  final live = ref.watch(publicAppConfigProvider).valueOrNull;
  if (live != null) return live.flowSignInV2;
  return ref.watch(cachedPublicAppConfigProvider)?.flowSignInV2 ??
      Environment.flowV2Default;
});

/// The Dating open-country list (D15): the Welcome preview, A6 and the Me
/// slot read it here and nowhere else. Empty until the config has been read.
/// Selected by value (batch 6 review #3): a re-read on resume that returns
/// the same config keeps the same list, so its watchers don't rebuild.
final datingOpenCountriesProvider = Provider<List<String>>((ref) {
  final live = ref.watch(
    publicAppConfigProvider.select((config) => config.valueOrNull),
  );
  if (live != null) return live.datingOpenCountries;
  return ref.watch(cachedPublicAppConfigProvider)?.datingOpenCountries ??
      const [];
});
