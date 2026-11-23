// Spec 2 (§3.0, §6.7; S1 §5.8, D19; R-9): Dating's entries in Spec 1's
// device wipe registry, reached by one line in lib/app/device_wipes.dart.
// W3a: the in-memory session (the Dating unlock, open setup answers). W8a
// adds the caches here; quick_exit_service.dart and auth_provider.dart are
// never edited. Nothing here is protective: the Dating lock stays.
// Spec 2 W8a (§6.7): the pages go blank first (order 0, before Spec 1's
// awaited entries), and §6.7's spec2.section_caches sweeps every Dating
// memory again after them (order 20). No entry touches the lock, the
// Safety PIN, the app icon or a scheduled check-in, and none awaits I/O
// but W8b's spec2.section_view (its one neutral keystore key).
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/device/dating_surface.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';

void registerDatingDeviceWipes([DeviceWipeRegistry? registry]) {
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.dating_session',
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      run: DatingSessionMemory.clear,
    ),
  );
  // Spec 2 W5b (§3.4, §6.7): the other people's photos held in memory.
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.dating_photos',
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      run: DatingPhotoMemory.clear,
    ),
  );
  // Spec 2 W6c (§3.6, D20): the meet plan held in memory.
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.dating_plan',
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      run: DatingPlanMemory.clear,
    ),
  );
  // Spec 2 W8a (§6.7; W6 final carry): no frame of Dating under the decoy.
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.dating_surface',
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      run: DatingSurface.hide,
    ),
  );
  // Spec 2 W8b (R-T4-9, Re4-I-2): a same-gender trip's note answer, the
  // one Dating mark this phone keeps (neutral key, the Safety keystore).
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.section_view',
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      keys: {DatingTripPhone.key},
      run: DatingTripPhone.clear,
    ),
  );
  // Spec 2 W8a (§6.7): every Dating memory again, after Spec 1's entries.
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.section_caches',
      order: 20,
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      run: clearDatingDeviceData,
    ),
  );
}

/// §6.7's sweep: the session (unlock, open answers, unsent dismissals, the
/// report and appeal keys), the other people's photos with their decoded
/// copies, and the meet plan with the check-in time the kit read. Memory
/// only: no I/O, no SharedPreferences, no platform channel, and the
/// check-in itself stays scheduled on the server (safety).
Future<void> clearDatingDeviceData() async {
  await DatingSessionMemory.clear();
  await DatingPhotoMemory.clear();
  await DatingPlanMemory.clear();
}
