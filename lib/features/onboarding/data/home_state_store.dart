import 'dart:convert';

import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The last server home state, as the phone may keep it (spec §5.5, D20):
/// the tab layout, the link state, the needs and whether a hold is on.
/// Never the path, never anything about Dating: Dating and Just for me both
/// cache `me`.
@immutable
class CachedHomeState {
  const CachedHomeState({
    required this.tab,
    required this.link,
    required this.needs,
    required this.hold,
    required this.at,
  });

  final AppTab tab;
  final LinkState link;
  final List<HomeNeed> needs;
  final bool hold;
  final DateTime at;

  bool get isComplete => needs.isEmpty;
}

/// User-scoped cache under `attune.home.<uid>.state`, written only from a
/// server answer so a local value is never invented. Its sign-out wipe
/// entry (`spec1.home_state_cache`) is registered in W3a.
class HomeStateStore {
  HomeStateStore(
    this._prefs, {
    required String userId,
    DateTime Function()? now,
  }) : _userId = userId,
       _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final String _userId;
  final DateTime Function() _now;

  static String keyFor(String userId) => 'attune.home.$userId.state';

  String get _key => keyFor(_userId);

  CachedHomeState? read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final at = DateTime.tryParse(json['at'] as String? ?? '');
      if (at == null) return null;
      return CachedHomeState(
        tab: AppTab.fromWire(json['tab']),
        link: LinkState.fromWire(json['link']),
        needs: HomeNeed.listFromWire(json['needs']),
        hold: json['hold'] == true,
        at: at,
      );
    } catch (_) {
      // A corrupt cache is dropped; the next server answer rewrites it.
      return null;
    }
  }

  Future<void> write(HomeState state) => _prefs.setString(
    _key,
    jsonEncode({
      'tab': state.tab.wire,
      'link': state.link.state.wire,
      'needs': [for (final need in state.needs) need.wire],
      'hold': state.hold,
      'at': _now().toUtc().toIso8601String(),
    }),
  );

  Future<void> clear() => _prefs.remove(_key);
}
