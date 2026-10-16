// test/features/location/presence_reads_hook_test.dart
import 'dart:async';

import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'presence_repository_test.dart' show FakePresenceGateway, FakeSampler;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container(FakePresenceGateway g) => ProviderContainer(
    overrides: [
      presenceGatewayProvider.overrideWithValue(g),
      presenceSamplerProvider.overrideWithValue(FakeSampler()),
      presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
    ],
  );

  test('every couple-map read is announced with its relationship', () async {
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
    final c = container(g);
    addTearDown(c.dispose);
    final heard = <(String, CoupleMapPresence)>[];
    c.read(presenceReadsProvider).stream.listen(heard.add);
    final sub = c.listen(coupleMapPresenceProvider('r1'), (_, __) {});
    await c.read(coupleMapPresenceProvider('r1').future);
    await Future<void>.delayed(Duration.zero);
    expect(heard.single.$1, 'r1');
    expect(heard.single.$2.state.status, PresenceStatus.paused);
    sub.close();
  });

  test(
    'listening to the hook never starts the couple-map provider (no sampling)',
    () async {
      final g = FakePresenceGateway({'couple_map_presence': (_) => const []});
      final c = container(g);
      addTearDown(c.dispose);
      c.read(presenceReadsProvider).stream.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(g.calls, isEmpty);
    },
  );
}
