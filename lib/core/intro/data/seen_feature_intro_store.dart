// lib/core/intro/data/seen_feature_intro_store.dart

import 'package:shared_preferences/shared_preferences.dart';

/// Tracks, per feature id, whether the first-time intro flow
/// (FeatureIntroFlowScreen) has already been shown on this device.
/// Mirrors QuizProgressStore's construction and keyed-prefix convention.
class SeenFeatureIntroStore {
  SeenFeatureIntroStore(this._prefs);

  final SharedPreferences _prefs;

  static const _keyPrefix = 'seen_feature_intro_';

  bool hasSeenIntro(String featureId) {
    return _prefs.getBool('$_keyPrefix$featureId') ?? false;
  }

  Future<void> markIntroSeen(String featureId) async {
    await _prefs.setBool('$_keyPrefix$featureId', true);
  }
}
