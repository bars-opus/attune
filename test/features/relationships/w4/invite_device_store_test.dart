// Spec 1 W4b (§3.8, §4.8, §5.8): the partner first name stays on this
// phone, per account; it goes on linking and at sign-out; the linked
// moment is once per phone and survives sign-out; nothing names Dating.
import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the name is per account, trimmed, at most 40 characters', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final mine = InviteDeviceStore(prefs, userId: 'u1');
    final theirs = InviteDeviceStore(prefs, userId: 'u2');
    await mine.savePartnerFirstName('  Ama ');
    expect(mine.partnerFirstName, 'Ama');
    expect(theirs.partnerFirstName, isNull);
    expect(prefs.getString('attune.flow.u1.partner_first_name'), 'Ama');
    await mine.savePartnerFirstName('A' * 60);
    expect(mine.partnerFirstName, hasLength(40));
    await mine.savePartnerFirstName('   ');
    expect(mine.partnerFirstName, isNull);
    expect(prefs.containsKey('attune.flow.u1.partner_first_name'), isFalse);
  });

  test('the linked moment: once per relationship, per account', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = InviteDeviceStore(prefs, userId: 'u1');
    expect(store.linkedMomentSeen('r1'), isFalse);
    await store.markLinkedMomentSeen('r1');
    expect(store.linkedMomentSeen('r1'), isTrue);
    expect(store.linkedMomentSeen('r2'), isFalse);
    expect(
      InviteDeviceStore(prefs, userId: 'u2').linkedMomentSeen('r1'),
      isFalse,
    );
    expect(prefs.getBool('attune.linked_moment:u1:r1'), isTrue);
  });

  test('sign-out removes every account\'s name and day-30 mark, keeps the '
      'linked moment', () async {
    SharedPreferences.setMockInitialValues({
      'attune.flow.u1.partner_first_name': 'Ama',
      'attune.flow.u2.partner_first_name': 'Kofi',
      'attune.flow.u1.invite_day30': true,
      'attune.linked_moment:u1:r1': true,
      'attune.flow.u1.other': 'kept',
    });
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    final entry = registry.entries.firstWhere(
      (e) => e.id == 'spec1.partner_first_name',
    );
    expect(entry.moments, {WipeMoment.signOut});
    expect(entry.protective, isFalse);
    await registry.run(WipeMoment.signOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('attune.flow.u1.partner_first_name'), isFalse);
    expect(prefs.containsKey('attune.flow.u2.partner_first_name'), isFalse);
    expect(prefs.containsKey('attune.flow.u1.invite_day30'), isFalse);
    expect(prefs.getBool('attune.linked_moment:u1:r1'), isTrue);
    expect(prefs.getString('attune.flow.u1.other'), 'kept');
  });

  test(
    'the full sign-out clear keeps the linked moment (keptPrefixes)',
    () async {
      SharedPreferences.setMockInitialValues({
        'attune.linked_moment:u1:r1': true,
        'attune.flow.u1.partner_first_name': 'Ama',
      });
      final prefs = await SharedPreferences.getInstance();
      await PreferencesService(prefs).clearUserData();
      expect(prefs.getBool('attune.linked_moment:u1:r1'), isTrue);
      expect(prefs.containsKey('attune.flow.u1.partner_first_name'), isFalse);
    },
  );

  test('no W4 key names Dating (D20)', () {
    for (final key in [
      InviteDeviceStore.partnerNameKey('u1'),
      InviteDeviceStore.day30Key('u1'),
      InviteDeviceStore.linkedMomentKey('u1', 'r1'),
    ]) {
      expect(key.toLowerCase(), isNot(contains('dating')));
    }
  });
}
