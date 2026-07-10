import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingStore {
  const OnboardingStore(this._prefs, {required String scope}) : _scope = scope;

  final SharedPreferences _prefs;
  final String _scope;

  static const userScopePrefix = 'user';
  static const previewScope = 'preview';
  static const anonymousScope = 'anonymous';

  static const _completedKey = 'completed';
  static const _modeKey = 'mode';
  static const _displayNameKey = 'display_name';
  static const pendingInviteCodeKey = 'attune.onboarding.pending_invite_code';

  bool get isComplete => _prefs.getBool(_key(_completedKey)) ?? false;

  OnboardingMode? get mode {
    final value = _prefs.getString(_key(_modeKey));
    if (value == null) return null;
    for (final mode in OnboardingMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  String? get displayName => _prefs.getString(_key(_displayNameKey));

  String? get pendingInviteCode => _prefs.getString(pendingInviteCodeKey);

  Future<void> storePendingInviteCode(String code) {
    return _prefs.setString(pendingInviteCodeKey, code);
  }

  Future<void> clearPendingInviteCode() {
    return _prefs.remove(pendingInviteCodeKey);
  }

  Future<void> complete({
    required OnboardingMode mode,
    required String displayName,
  }) async {
    await _prefs.setString(_key(_modeKey), mode.name);
    await _prefs.setString(_key(_displayNameKey), displayName);
    await _prefs.setBool(_key(_completedKey), true);
  }

  Future<void> reset() async {
    await _prefs.remove(_key(_completedKey));
    await _prefs.remove(_key(_modeKey));
    await _prefs.remove(_key(_displayNameKey));
    await _prefs.remove(pendingInviteCodeKey);
  }

  String _key(String key) => 'attune.onboarding.$_scope.$key';
}
