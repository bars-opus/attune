// Spec 2 (§3.0, §6.7; S1 §5.8, D19; R-9): Dating's entries in Spec 1's
// device wipe registry, reached by one line in lib/app/device_wipes.dart.
// W3a: the in-memory session (the Dating unlock, open setup answers). W8a
// adds the caches here; quick_exit_service.dart and auth_provider.dart are
// never edited. Nothing here is protective: the Dating lock stays.
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';

void registerDatingDeviceWipes([DeviceWipeRegistry? registry]) {
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.dating_session',
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      run: DatingSessionMemory.clear,
    ),
  );
}
