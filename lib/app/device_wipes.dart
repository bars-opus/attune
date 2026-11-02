import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/platform/install_referrer_keys.dart';
import 'package:attune/features/onboarding/data/ask2_progress_store.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every feature's device wipes, registered once at boot (main.dart; spec
/// §5.8). Spec 1's entries are here; another feature adds one line calling
/// its own register function (Spec 2: `registerDatingDeviceWipes(registry)`).
void registerDeviceWipes([DeviceWipeRegistry? registry]) {
  final target = registry ?? DeviceWipeRegistry.instance;
  for (final entry in spec1DeviceWipes()) {
    target.register(entry);
  }
}

/// Removes every prefs key [matches] accepts (all accounts on the phone:
/// the next person to sign in here inherits none of them).
Future<void> removePrefsKeys(bool Function(String key) matches) async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in prefs.getKeys().where(matches).toList()) {
    await prefs.remove(key);
  }
}

/// `attune.home.<uid>.state` (HomeStateStore.keyFor).
bool isHomeStateKey(String key) =>
    key.startsWith('attune.home.') && key.endsWith('.state');

/// Spec 1's entries (spec §5.8 table).
List<DeviceWipeEntry> spec1DeviceWipes() => [
  DeviceWipeEntry(
    id: 'spec1.home_state_cache',
    moments: const {WipeMoment.signOut},
    keys: const {'attune.home.<uid>.state'},
    run: () => removePrefsKeys(isHomeStateKey),
  ),
  // W3b: the Dating lock is protective: sign-out only, never quick exit
  // (D19).
  DeviceWipeEntry(
    id: 'spec1.dating_lock',
    moments: const {WipeMoment.signOut},
    protective: true,
    keys: const {DatingLockStore.key},
    run: () => DatingLockStore().clear(),
  ),
  // W3b: the Me home's country and J1 progress.
  DeviceWipeEntry(
    id: 'spec1.me_device',
    moments: const {WipeMoment.signOut},
    keys: const {
      'attune.flow.<uid>.country_override',
      'attune.flow.<uid>.first_action',
    },
    run:
        () => removePrefsKeys(
          (key) =>
              key.startsWith('attune.flow.') &&
              (key.endsWith('.country_override') ||
                  key.endsWith('.first_action')),
        ),
  ),
  // W4b (§3.8 R1, R3): R1's partner first name and R3's day-30 line, at
  // sign-out, for every account on the phone.
  DeviceWipeEntry(
    id: 'spec1.partner_first_name',
    moments: const {WipeMoment.signOut},
    keys: const {
      'attune.flow.<uid>.partner_first_name',
      'attune.flow.<uid>.invite_day30',
    },
    run: () => removePrefsKeys(InviteDeviceStore.isWipedOnSignOut),
  ),
  // W4b (§3.8 R5): Ask 2's saved answers, at sign-out and on quick exit.
  DeviceWipeEntry(
    id: 'spec1.ask2_progress',
    moments: const {WipeMoment.signOut, WipeMoment.quickExit},
    keys: const {'attune.ask2.<uid>.<relationshipId>'},
    run: () => removePrefsKeys(Ask2ProgressStore.isProgressKey),
  ),
  // Final review #1: the Install Referrer's RI-1 prefill, at sign-out and
  // on quick exit (the read-once mark is kept: PreferencesService.keptKeys).
  DeviceWipeEntry(
    id: 'spec1.install_referrer_code',
    moments: const {WipeMoment.signOut, WipeMoment.quickExit},
    keys: const {kInstallReferrerCodeKey},
    run: () => removePrefsKeys((key) => key == kInstallReferrerCodeKey),
  ),
];
