import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a player has switched on in the games' settings sheet.
@immutable
class GamePrefs {
  const GamePrefs({this.sound = true, this.haptics = true});

  final bool sound;
  final bool haptics;

  @override
  bool operator ==(Object other) =>
      other is GamePrefs && other.sound == sound && other.haptics == haptics;

  @override
  int get hashCode => Object.hash(sound, haptics);
}

/// Per device, not per account: whether a phone should make noise is about
/// the phone and where it is, not about the person.
class GamePrefsNotifier extends Notifier<GamePrefs> {
  static const String soundKey = 'games.sound_effects';
  static const String hapticsKey = 'games.haptics';

  @override
  GamePrefs build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return GamePrefs(
      sound: prefs.getBool(soundKey) ?? true,
      haptics: prefs.getBool(hapticsKey) ?? true,
    );
  }

  void setSound(bool value) {
    state = GamePrefs(sound: value, haptics: state.haptics);
    unawaited(ref.read(sharedPreferencesProvider).setBool(soundKey, value));
  }

  void setHaptics(bool value) {
    state = GamePrefs(sound: state.sound, haptics: value);
    unawaited(ref.read(sharedPreferencesProvider).setBool(hapticsKey, value));
  }
}

final gamePrefsProvider = NotifierProvider<GamePrefsNotifier, GamePrefs>(
  GamePrefsNotifier.new,
);
