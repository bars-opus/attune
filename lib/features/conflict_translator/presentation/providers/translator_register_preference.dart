import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/conflict_translator/data/models/translator_request.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spec 8 (plan review M5): NVC or plain words, remembered on this device
/// only.
const _kKey = 'translator_register';

class TranslatorRegisterNotifier extends StateNotifier<TranslatorRegister> {
  TranslatorRegisterNotifier(SharedPreferences prefs)
    : _prefs = prefs,
      super(
        prefs.getString(_kKey) == 'plain'
            ? TranslatorRegister.plain
            : TranslatorRegister.nvc,
      );

  final SharedPreferences _prefs;

  Future<void> set(TranslatorRegister register) async {
    state = register;
    await _prefs.setString(_kKey, register.name);
  }
}

final translatorRegisterProvider =
    StateNotifierProvider<TranslatorRegisterNotifier, TranslatorRegister>(
      (ref) => TranslatorRegisterNotifier(ref.watch(sharedPreferencesProvider)),
    );
