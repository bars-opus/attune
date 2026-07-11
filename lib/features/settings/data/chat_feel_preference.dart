import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How expressive the chat delight moments are. Warm-calm by default; the user
/// may opt into more expressive rituals (Spec §1.1 tone floor, §3.7).
enum ChatExpressiveness { calm, expressive }

const _kKey = 'chat_expressiveness';

class ChatFeelPreferenceNotifier extends StateNotifier<ChatExpressiveness> {
  ChatFeelPreferenceNotifier(SharedPreferences prefs)
      : _prefs = prefs,
        super(_read(prefs));

  /// Test-only constructor that skips the SharedPreferences-backed default,
  /// for callers (e.g. chat widget test harnesses) that need to override
  /// [chatExpressivenessProvider] synchronously without an async
  /// `SharedPreferences.getInstance()`. Persistence is a no-op.
  ChatFeelPreferenceNotifier.forTesting([
    super.initial = ChatExpressiveness.calm,
  ]) : _prefs = null;

  final SharedPreferences? _prefs;

  static ChatExpressiveness _read(SharedPreferences prefs) {
    return prefs.getString(_kKey) == 'expressive'
        ? ChatExpressiveness.expressive
        : ChatExpressiveness.calm;
  }

  Future<void> setExpressiveness(ChatExpressiveness value) async {
    state = value;
    await _prefs?.setString(_kKey, value.name);
  }
}

final chatExpressivenessProvider =
    StateNotifierProvider<ChatFeelPreferenceNotifier, ChatExpressiveness>((ref) {
  return ChatFeelPreferenceNotifier(ref.watch(sharedPreferencesProvider));
});
