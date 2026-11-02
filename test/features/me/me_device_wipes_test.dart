// Spec 1 W3b (§5.8, D20): the Me home's device keys (the country the Dating
// slot uses, J1's progress) go on sign-out, for every account on the phone.
import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test("sign-out clears every account's Me keys and nothing else", () async {
    SharedPreferences.setMockInitialValues({
      'attune.flow.u1.country_override': 'GH',
      'attune.flow.u2.first_action': 'started',
      'attune.flow.u1.other': 'kept',
    });
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    expect(registry.entries.map((e) => e.id), contains('spec1.me_device'));
    await registry.run(WipeMoment.signOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'attune.flow.u1.other'});
  });
}
