import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kMessageSoundsKey = 'chat_message_sounds_enabled';

/// Persists the "Message sounds" toggle. Default on (Spec §3.6).
class SoundPreferenceNotifier extends StateNotifier<bool> {
  SoundPreferenceNotifier(this._prefs)
    : super(_prefs.getBool(_kMessageSoundsKey) ?? true);

  final SharedPreferences _prefs;

  Future<void> setEnabled(bool value) async {
    state = value;
    await _prefs.setBool(_kMessageSoundsKey, value);
  }

  Future<void> toggle() => setEnabled(!state);
}

final messageSoundsEnabledProvider =
    StateNotifierProvider<SoundPreferenceNotifier, bool>((ref) {
  return SoundPreferenceNotifier(ref.watch(sharedPreferencesProvider));
});
