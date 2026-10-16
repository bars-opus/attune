// test/features/location/presence_providers_test.dart
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:flutter_test/flutter_test.dart';

import 'presence_repository_test.dart' show FakePresenceGateway, FakeSampler;

const _accra = PresenceSample(
  lat: 5.56,
  lng: -0.2,
  accuracyM: 40,
  city: 'Accra',
);

ProviderContainer _container(FakePresenceGateway g, FakeSampler s) {
  final c = ProviderContainer(
    overrides: [
      presenceGatewayProvider.overrideWithValue(g),
      presenceSamplerProvider.overrideWithValue(s),
      presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('not sharing: never samples and never asks for permission', () async {
    final g = FakePresenceGateway({'couple_map_presence': (_) => const []});
    final s = FakeSampler(next: _accra);
    final c = _container(g, s);
    final p = await c.read(coupleMapPresenceProvider('r1').future);
    expect(p.state.status, PresenceStatus.off);
    expect(s.sampled, 0);
    expect(s.asked, 0);
    expect(g.calls.where((x) => x.$1 == 'record_presence'), isEmpty);
  });

  test(
    'sharing: samples once on open, records, then reads the fresh state',
    () async {
      final g = FakePresenceGateway({
        'couple_map_presence':
            (_) => const [
              {
                'who': 'self',
                'cell_lat': 5.565,
                'cell_lng': -0.205,
                'freshness': 'fresh',
              },
            ],
      });
      final s = FakeSampler(next: _accra);
      final c = _container(g, s);
      await c.read(coupleMapPresenceProvider('r1').future);
      expect(s.sampled, 1);
      expect(g.calls.map((x) => x.$1), [
        'couple_map_presence',
        'record_presence',
        'couple_map_presence',
      ]);
    },
  );

  test('paused: no sampling', () async {
    final g = FakePresenceGateway({
      'couple_map_presence':
          (_) => const [
            {
              'who': 'self',
              'freshness': 'fresh',
              'my_paused_until': '2099-01-01T00:00:00Z',
            },
          ],
    });
    final s = FakeSampler(next: _accra);
    final c = _container(g, s);
    final state = (await c.read(coupleMapPresenceProvider('r1').future)).state;
    expect(state.status, PresenceStatus.paused);
    expect(s.sampled, 0);
  });

  test('paused until resumed (infinity): no sampling', () async {
    final g = FakePresenceGateway({
      'couple_map_presence':
          (_) => const [
            {
              'who': 'self',
              'freshness': 'fresh',
              'my_paused_until': 'infinity',
            },
          ],
    });
    final s = FakeSampler(next: _accra);
    final c = _container(g, s);
    final state = (await c.read(coupleMapPresenceProvider('r1').future)).state;
    expect(state.status, PresenceStatus.paused);
    expect(s.sampled, 0);
  });

  test(
    'a failed refresh keeps the last known state (an error, not "off")',
    () async {
      var fail = false;
      final g = FakePresenceGateway({
        'couple_map_presence': (_) {
          if (fail) throw Exception('offline');
          return const [
            {
              'who': 'self',
              'cell_lat': 5.565,
              'cell_lng': -0.205,
              'freshness': 'fresh',
            },
          ];
        },
      });
      final c = _container(g, FakeSampler(next: _accra));
      final sub = c.listen(presenceStateProvider('r1'), (_, __) {});
      addTearDown(sub.close);
      await c.read(coupleMapPresenceProvider('r1').future);
      fail = true;
      c.invalidate(coupleMapPresenceProvider('r1'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final state = c.read(presenceStateProvider('r1'));
      expect(state.hasError, isTrue);
      expect(state.valueOrNull?.status, PresenceStatus.sharing);
    },
  );

  test('location access is read without prompting', () async {
    final g = FakePresenceGateway();
    final s = FakeSampler()..accessValue = LocationAccess.denied;
    final c = _container(g, s);
    expect(await c.read(locationAccessProvider.future), LocationAccess.denied);
    expect(s.asked, 0);
  });
}
