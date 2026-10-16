// test/features/location/presence_repository_test.dart
import 'package:attune/features/location/data/presence_gateway.dart';
import 'package:attune/features/location/data/presence_repository.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/foundation.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePresenceGateway implements PresenceGateway {
  FakePresenceGateway([
    Map<String, dynamic Function(Map<String, dynamic>)>? handlers,
  ]) : handlers = handlers ?? {};
  final Map<String, dynamic Function(Map<String, dynamic>)> handlers;
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) async {
    calls.add((fn, params ?? const {}));
    final h = handlers[fn];
    if (h == null) return null;
    return h(params ?? const {});
  }
}

class FakeSampler implements PresenceSampler {
  FakeSampler({this.next, this.grant = true});
  PresenceSample? next;
  bool grant;
  int asked = 0;
  int sampled = 0;
  @override
  Future<PresenceSample?> sample() async {
    sampled++;
    return next;
  }

  @override
  Future<bool> requestPermission() async {
    asked++;
    return grant;
  }

  LocationAccess accessValue = LocationAccess.granted;
  int openedSettings = 0;
  @override
  Future<LocationAccess> access() async => accessValue;
  @override
  Future<void> openSettings() async => openedSettings++;
}

const _accra = PresenceSample(
  lat: 5.5603,
  lng: -0.2057,
  accuracyM: 40,
  city: 'Accra',
  country: 'Ghana',
  countryCode: 'GH',
);

PresenceRepository _repo(FakePresenceGateway g, FakeSampler s) =>
    PresenceRepository(g, s, () async => 'Africa/Accra');

void main() {
  test('start opts in, asks for permission once, then records', () async {
    final g = FakePresenceGateway();
    final s = FakeSampler(next: _accra);
    await _repo(g, s).startSharing('r1');
    expect(g.calls.map((c) => c.$1), ['start_presence', 'record_presence']);
    expect(s.asked, 1);
    final rec = g.calls.last.$2;
    expect(rec['p_relationship_id'], 'r1');
    expect(rec['p_accuracy_m'], 40);
    expect(rec['p_timezone'], 'Africa/Accra');
  });

  test(
    'no fix (permission off, timeout): nothing recorded, no error',
    () async {
      final g = FakePresenceGateway();
      final ok = await _repo(g, FakeSampler(next: null)).record('r1');
      expect(ok, isFalse);
      expect(g.calls, isEmpty);
    },
  );

  test(
    'pause sends a bounded end, or infinity until resumed; resume sends null',
    () async {
      final g = FakePresenceGateway();
      final r = _repo(g, FakeSampler());
      await r.pause('r1', const Duration(hours: 1));
      await r.pause('r1', null);
      await r.resume('r1');
      expect(
        DateTime.parse(
          g.calls[0].$2['p_until'] as String,
        ).isAfter(DateTime.now().toUtc()),
        isTrue,
      );
      expect(g.calls[1].$2['p_until'], 'infinity');
      expect(g.calls[2].$2['p_until'], isNull);
    },
  );

  test('stop calls stop_presence (deletes, silently)', () async {
    final g = FakePresenceGateway();
    await _repo(g, FakeSampler()).stopSharing('r1');
    expect(g.calls.single.$1, 'stop_presence');
  });

  test(
    'fetchMapPresence maps rows; a failure is an error, never "off"',
    () async {
      final g = FakePresenceGateway({
        'couple_map_presence':
            (_) => [
              {
                'who': 'self',
                'cell_lat': 5.565,
                'cell_lng': -0.205,
                'city': 'Accra',
                'freshness': 'fresh',
              },
            ],
      });
      final p = await _repo(g, FakeSampler()).fetchMapPresence('r1');
      expect(p.state.status, PresenceStatus.sharing);
      // An unknown state must not read as "not sharing": the privacy toggle
      // would show Off for someone whose area is still shared.
      g.handlers['couple_map_presence'] = (_) => throw Exception('offline');
      await expectLater(
        _repo(g, FakeSampler()).fetchMapPresence('r1'),
        throwsA(isA<Exception>()),
      );
    },
  );

  test(
    'a failed record never logs coordinates or the city (checklist 4.4)',
    () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = original);
      final g = FakePresenceGateway({
        'record_presence': (_) => throw Exception('lat 5.5603 Accra'),
      });
      await _repo(g, FakeSampler(next: _accra)).record('r1');
      expect(logs, isNotEmpty);
      for (final l in logs) {
        expect(l.contains('5.56'), isFalse);
        expect(l.contains('Accra'), isFalse);
      }
    },
  );

  test(
    'a second automatic record within 60 s is skipped on the device (checklist 3.7)',
    () async {
      var now = DateTime.utc(2026, 10, 16, 12);
      final g = FakePresenceGateway();
      final s = FakeSampler(next: _accra);
      final r = PresenceRepository(
        g,
        s,
        () async => 'Africa/Accra',
        now: () => now,
      );
      expect(await r.record('r1'), isTrue);
      now = now.add(const Duration(seconds: 30));
      expect(await r.record('r1'), isFalse);
      expect(
        s.sampled,
        1,
        reason: 'no GPS fix or geocode for a write the server would ignore',
      );
      now = now.add(const Duration(seconds: 31));
      expect(await r.record('r1'), isTrue);
      expect(s.sampled, 2);
    },
  );

  test(
    'opting in and resuming always record at once, whatever the debounce',
    () async {
      final now = DateTime.utc(2026, 10, 16, 12);
      final g = FakePresenceGateway();
      final s = FakeSampler(next: _accra);
      final r = PresenceRepository(
        g,
        s,
        () async => 'Africa/Accra',
        now: () => now,
      );
      await r.record('r1');
      await r.startSharing('r1');
      expect(s.sampled, 2);
      await r.resume('r1');
      expect(
        await r.record('r1'),
        isTrue,
        reason: 'resume needs a fresh sample (spec §4.2)',
      );
    },
  );
}
