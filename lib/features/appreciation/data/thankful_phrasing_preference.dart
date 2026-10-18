import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spec 7 (plan ruling P2): offer "Thankful for you because…" beside
/// "I noticed you…". Off by default, kept on this device only; nothing is
/// inferred from it and it is never sent as a setting.
const _kKey = 'appreciation_thankful_phrasing';

class ThankfulPhrasingNotifier extends StateNotifier<bool> {
  ThankfulPhrasingNotifier(SharedPreferences prefs)
    : _prefs = prefs,
      super(prefs.getBool(_kKey) ?? false);

  final SharedPreferences _prefs;

  Future<void> set(bool on) async {
    state = on;
    await _prefs.setBool(_kKey, on);
  }
}

final thankfulPhrasingProvider =
    StateNotifierProvider<ThankfulPhrasingNotifier, bool>(
      (ref) => ThankfulPhrasingNotifier(ref.watch(sharedPreferencesProvider)),
    );
