// Spec 2 review M-7: signing out keeps each account's known-sessions
// baseline (it is keyed by user id), so the next sign-in is not a "first
// run" that repeats the one-time review notice or hides a new device.
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('clearUserData keeps account_known_sessions:<uid>', () async {
    SharedPreferences.setMockInitialValues({
      'account_known_sessions:u1': '["s1"]',
      'some_user_thing': true,
    });
    final prefs = await SharedPreferences.getInstance();
    await PreferencesService(prefs).clearUserData();
    expect(prefs.getString('account_known_sessions:u1'), '["s1"]');
    expect(prefs.containsKey('some_user_thing'), isFalse);
  });
}
