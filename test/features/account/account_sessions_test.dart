// Spec 2 (research 06 §3 F7 (1), (2)): the sessions repository and the pure
// new-session diff.
import 'package:attune/features/account/data/account_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

SignedInDevice _d(String id, {bool current = false}) => SignedInDevice(
  sessionId: id,
  label: 'Android phone',
  platform: 'android',
  signedInAt: DateTime.utc(2026, 10, 1),
  lastActiveAt: DateTime.utc(2026, 10, 2),
  isCurrent: current,
);

void main() {
  test('fromRow parses all six fields', () {
    final d = SignedInDevice.fromRow({
      'session_id': 's1',
      'device_label': 'iPhone or iPad · iOS 17.2',
      'platform': 'ios',
      'signed_in_at': '2026-10-01T08:00:00Z',
      'last_active_at': '2026-10-02T09:30:00+00:00',
      'is_current': true,
    });
    expect(d.sessionId, 's1');
    expect(d.label, 'iPhone or iPad · iOS 17.2');
    expect(d.platform, 'ios');
    expect(d.signedInAt, DateTime.utc(2026, 10, 1, 8));
    expect(d.lastActiveAt, DateTime.utc(2026, 10, 2, 9, 30));
    expect(d.isCurrent, isTrue);
  });

  test('fromRow keeps an unnamed device unnamed', () {
    final d = SignedInDevice.fromRow({
      'session_id': 's2',
      'device_label': null,
      'platform': null,
      'signed_in_at': '2026-10-01T08:00:00Z',
      'last_active_at': '2026-10-01T08:00:00Z',
      'is_current': false,
    });
    expect(d.label, isNull);
    expect(d.platform, isNull);
    expect(d.isCurrent, isFalse);
  });

  group('repository', () {
    late List<(String, Map<String, dynamic>?)> calls;
    late int signOuts;
    late AccountSessionsRepository repo;

    setUp(() {
      calls = [];
      signOuts = 0;
      repo = AccountSessionsRepository((fn, [params]) async {
        calls.add((fn, params));
        if (fn == 'list_my_sessions') {
          return [
            {
              'session_id': 's1',
              'device_label': 'Android phone',
              'platform': 'android',
              'signed_in_at': '2026-10-01T08:00:00Z',
              'last_active_at': '2026-10-02T08:00:00Z',
              'is_current': true,
            },
          ];
        }
        return null;
      }, () async => signOuts++);
    });

    test('list() calls list_my_sessions', () async {
      final list = await repo.list();
      expect(calls.single.$1, 'list_my_sessions');
      expect(list.single.sessionId, 's1');
    });

    test('registerThisDevice() sends the label and platform', () async {
      await repo.registerThisDevice();
      expect(calls.single.$1, 'register_my_device');
      expect(calls.single.$2!.keys, containsAll(['p_label', 'p_platform']));
      expect(calls.single.$2!['p_platform'], thisDevicePlatform());
      expect(calls.single.$2!['p_label'], thisDeviceLabel());
    });

    test('signOutOtherDevices() calls the injected sign-out', () async {
      await repo.signOutOtherDevices();
      expect(signOuts, 1);
      expect(calls, isEmpty);
    });
  });

  group('newSessionIds', () {
    test('first run reports nothing', () {
      expect(newSessionIds(known: null, now: [_d('a'), _d('b')]), isEmpty);
    });
    test('a session not seen before is new', () {
      expect(newSessionIds(known: {'a'}, now: [_d('a'), _d('b')]), {'b'});
    });
    test('this phone is never new', () {
      expect(
        newSessionIds(known: {'a'}, now: [_d('c', current: true)]),
        isEmpty,
      );
    });
    test('a session that went away is not new', () {
      expect(newSessionIds(known: {'a'}, now: const []), isEmpty);
    });
  });

  test('labels and platforms stay inside the server limits', () {
    expect(thisDeviceLabel().length, lessThanOrEqualTo(60));
    expect(['ios', 'android', 'web', 'other'], contains(thisDevicePlatform()));
  });
}
