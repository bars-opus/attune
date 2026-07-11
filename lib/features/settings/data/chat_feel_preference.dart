import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How expressive the chat delight moments are. Warm-calm by default; the user
/// may opt into more expressive rituals (Spec §1.1 tone floor, §3.7).
enum ChatExpressiveness { calm, expressive }

const _kKey = 'chat_expressiveness';

class ChatFeelPreferenceNotifier extends StateNotifier<ChatExpressiveness> {
  ChatFeelPreferenceNotifier(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;

  static ChatExpressiveness _read(SharedPreferences prefs) {
    return prefs.getString(_kKey) == 'expressive'
        ? ChatExpressiveness.expressive
        : ChatExpressiveness.calm;
  }

  Future<void> setExpressiveness(ChatExpressiveness value) async {
    state = value;
    await _prefs.setString(_kKey, value.name);
  }
}

final chatExpressivenessProvider =
    StateNotifierProvider<ChatFeelPreferenceNotifier, ChatExpressiveness>((ref) {
  return ChatFeelPreferenceNotifier(ref.watch(sharedPreferencesProvider));
});
