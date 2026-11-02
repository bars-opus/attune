import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The Dating lock (Spec 1 §3.9, Q6): "Ask for your Safety PIN before
/// showing Dating." A device setting in the safety keystore (this phone
/// only, excluded from backups), under the neutral key `me_section_lock`
/// (D20: no "dating" in a device key or value). Protective: quick exit
/// never clears it; sign-out does (D19, §5.8 `spec1.dating_lock`).
class DatingLockStore {
  DatingLockStore({FlutterSecureStorage? storage})
    : _storage = storage ?? SafetyPinStore.defaultStorage;

  final FlutterSecureStorage _storage;

  static const key = 'me_section_lock';

  Future<bool> isOn() async => (await _storage.read(key: key)) == 'on';

  Future<void> setOn(bool on) =>
      on ? _storage.write(key: key, value: 'on') : _storage.delete(key: key);

  Future<void> clear() => _storage.delete(key: key);
}

final datingLockStoreProvider = Provider<DatingLockStore>(
  (ref) => DatingLockStore(),
);

/// The signed-in account's id, followed through sign-in and sign-out
/// (review I-1): the lock is read again from storage whenever it changes,
/// so what a sign-out wiped is what the next account (or the same one,
/// back) sees. A seam: tests drive it.
final datingLockAccountProvider = StreamProvider<String?>((ref) {
  final auth = PasswordlessAuthService();
  return Stream<String?>.multi((controller) {
    controller.add(auth.currentUser?.id);
    final sub = auth.authStateChanges
        .map((event) => event.session?.user.id)
        .listen(controller.add, onError: (Object _) {});
    controller.onCancel = sub.cancel;
  });
});

/// Whether the Dating lock is on, on this phone.
class DatingLockNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    // Per account (review I-1): a sign-out or another account reads again.
    await ref.watch(datingLockAccountProvider.selectAsync((id) => id));
    return ref.read(datingLockStoreProvider).isOn();
  }

  Future<void> set(bool on) async {
    await ref.read(datingLockStoreProvider).setOn(on);
    state = AsyncData(on);
  }
}

final datingLockProvider = AsyncNotifierProvider<DatingLockNotifier, bool>(
  DatingLockNotifier.new,
);
