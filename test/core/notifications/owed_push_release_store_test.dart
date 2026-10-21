// test/core/notifications/owed_push_release_store_test.dart
//
// Plan 1b final review I1: the owed push release lives in the OS keystore,
// where sign-out's clearUserData() (SharedPreferences) cannot wipe it.
import 'package:attune/core/notifications/data/owed_push_release_store.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const id = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('write, read, clear', () async {
    final store = SecureOwedPushReleaseStore();
    expect(await store.read(), isNull);
    await store.write(id);
    expect(await store.read(), id);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('an empty value is nothing owed', () async {
    FlutterSecureStorage.setMockInitialValues({'owed_push_release': ''});
    expect(await SecureOwedPushReleaseStore().read(), isNull);
  });

  test('survives the sign-out wipe of user preferences', () async {
    final store = SecureOwedPushReleaseStore();
    await store.write(id);
    final prefs = await SharedPreferences.getInstance();
    await PreferencesService(prefs).clearUserData();
    expect(await store.read(), id);
  });
}
