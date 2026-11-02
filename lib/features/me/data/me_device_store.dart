import 'package:shared_preferences/shared_preferences.dart';

/// Where J1 stands on this phone (Spec 1 §3.10).
enum FirstActionStage { none, started, celebrated }

/// The Me home's device keys, per account (spec §5.5): the country the
/// Dating slot uses instead of the phone number's (`country_override`, a
/// neutral name, D20) and how far J1 got. Both go on sign-out (§5.8).
class MeDeviceStore {
  MeDeviceStore(this._prefs, {required String userId}) : _userId = userId;

  final SharedPreferences _prefs;
  final String _userId;

  static String countryKey(String userId) =>
      'attune.flow.$userId.country_override';
  static String firstActionKey(String userId) =>
      'attune.flow.$userId.first_action';

  /// An ISO 3166-1 alpha-2 code, or null.
  String? get countryOverride {
    final value = _prefs.getString(countryKey(_userId));
    return value != null && RegExp(r'^[A-Z]{2}$').hasMatch(value)
        ? value
        : null;
  }

  Future<void> setCountryOverride(String iso) =>
      _prefs.setString(countryKey(_userId), iso.toUpperCase());

  FirstActionStage get firstAction => switch (_prefs.getString(
    firstActionKey(_userId),
  )) {
    'started' => FirstActionStage.started,
    'celebrated' => FirstActionStage.celebrated,
    _ => FirstActionStage.none,
  };

  Future<void> setFirstAction(FirstActionStage stage) =>
      _prefs.setString(firstActionKey(_userId), stage.name);
}
